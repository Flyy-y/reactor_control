-- Load required modules using dofile
local network = dofile("/reactor_control/shared/network.lua")
local protocol = dofile("/reactor_control/shared/protocol.lua")
local rules = dofile("/reactor_control/server/rules.lua")
local storage = dofile("/reactor_control/server/storage.lua")

local config = dofile("/reactor_control/server/config.lua")

local lastSaveTime = os.epoch("utc")
local componentStatus = {}

local function init()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Reactor Control Server ===")
    print("Initializing...")
    
    local channels = {config.modem_channel}
    for _, ch in ipairs(config.reactor_channels) do
        table.insert(channels, ch)
    end
    table.insert(channels, config.battery_channel)
    for _, ch in ipairs(config.display_channels) do
        table.insert(channels, ch)
    end
    
    network.init(nil, channels, config.privateKey)
    storage.init(config)
    
    storage.log("Server started")
    print("Server ready on channel " .. config.modem_channel)
end

local function handleReactorStatus(message, channel)
    local data = message.data
    rules.updateReactorState(data.reactor_id, data)
    storage.addReactorData(data.reactor_id, data)
    
    componentStatus["reactor_" .. data.reactor_id] = os.epoch("utc")
    
    local decision = rules.getReactorDecision(data.reactor_id, config)
    storage.addDecision(decision)
    
    if decision.action ~= "none" then
        local controlMsg = network.createMessage(
            protocol.messageTypes.REQUEST,
            protocol.commands.REACTOR_CONTROL,
            protocol.createReactorControl(
                data.reactor_id,
                decision.action,
                decision.burn_rate
            )
        )
        
        network.send(protocol.getReactorChannel(data.reactor_id), controlMsg)
        storage.log(string.format("Reactor %d: %s - %s", 
            data.reactor_id, decision.action, decision.reason))
    end
end

local function handleBatteryStatus(message, channel)
    local data = message.data
    rules.updateBatteryState(data)
    storage.addBatteryData(data)
    
    componentStatus["battery"] = os.epoch("utc")
end

local function handleDisplayRequest(message, channel)
    local requestType = message.data.type
    local response = nil
    
    if requestType == "system_status" then
        response = rules.getSystemStatus()
    elseif requestType == "reactor_history" then
        response = storage.getReactorHistory(
            message.data.reactor_id,
            message.data.count or 100
        )
    elseif requestType == "battery_history" then
        response = storage.getBatteryHistory(message.data.count or 100)
    elseif requestType == "alerts" then
        response = storage.getRecentAlerts(message.data.count or 50)
    elseif requestType == "stats" then
        response = storage.getStats()
    end
    
    if response then
        network.respond(message, response, "ok")
    else
        network.respond(message, {error = "Unknown request type"}, "error")
    end
end

local function handleHeartbeat(message, channel)
    componentStatus[message.data.component_type .. "_" .. message.data.component_id] = os.epoch("utc")
end

local function checkAndSendAlerts()
    local alerts = rules.checkAlerts(config)
    
    for _, alert in ipairs(alerts) do
        storage.addAlert(alert)
        
        local alertMsg = network.createMessage(
            protocol.messageTypes.BROADCAST,
            protocol.commands.ALERT,
            protocol.createAlert(
                alert.level,
                alert.source,
                alert.message
            )
        )
        
        network.broadcast(alertMsg)
        storage.log("ALERT [" .. alert.level .. "] " .. alert.source .. ": " .. alert.message)
    end
end

local function periodicTasks()
    checkAndSendAlerts()
    
    local health = rules.checkComponentHealth(config)
    for component, isHealthy in pairs(health.reactors) do
        if not isHealthy then
            storage.log("WARNING: Reactor " .. component .. " not responding")
        end
    end
    
    if not health.battery then
        storage.log("WARNING: Battery controller not responding")
    end
    
    local now = os.epoch("utc")
    if now - lastSaveTime > (config.data_retention.save_interval * 1000) then
        storage.save()
        lastSaveTime = now
    end
end

local function displayStatus()
    local x, y = term.getCursorPos()
    term.setCursorPos(1, 3)
    term.clearLine()
    
    local status = rules.getSystemStatus()
    local reactorCount = 0
    local activeCount = 0
    
    for id, reactor in pairs(status.reactors) do
        reactorCount = reactorCount + 1
        if reactor.active then
            activeCount = activeCount + 1
        end
    end
    
    print(string.format("Reactors: %d/%d active", activeCount, reactorCount))
    
    if status.battery then
        term.clearLine()
        print(string.format("Battery: %.1f%% (%.0f RF/t)", 
            status.battery.percent_full or 0,
            (status.battery.input_rate or 0) - (status.battery.output_rate or 0)
        ))
    end
    
    term.setCursorPos(x, y)
end

local function handleDiscoverReactors(message, channel)
    -- Server tracks all known reactors
    local reactorList = {}
    for id, _ in pairs(rules.getSystemStatus().reactors or {}) do
        table.insert(reactorList, id)
    end
    
    network.respond(message, {reactors = reactorList}, "ok")
end

local function setupHandlers()
    network.on(protocol.commands.REACTOR_STATUS, handleReactorStatus)
    network.on(protocol.commands.BATTERY_STATUS, handleBatteryStatus)
    network.on(protocol.commands.DISPLAY_REQUEST, handleDisplayRequest)
    network.on(protocol.commands.HEARTBEAT, handleHeartbeat)
    network.on(protocol.commands.DISCOVER_REACTORS, handleDiscoverReactors)
end

local function main()
    init()
    setupHandlers()
    
    local updateTimer = os.startTimer(config.update_interval)
    local displayTimer = os.startTimer(1)
    
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "modem_message" then
            network.handleModemMessage(p1, p2, p3, p4, p5)
        elseif event == "timer" then
            if p1 == updateTimer then
                periodicTasks()
                updateTimer = os.startTimer(config.update_interval)
            elseif p1 == displayTimer then
                displayStatus()
                displayTimer = os.startTimer(1)
            end
        elseif event == "key" and p1 == keys.q then
            storage.log("Server shutdown by user")
            storage.save()
            break
        end
    end
end

local success, err = pcall(main)
if not success then
    print("Server error: " .. tostring(err))
    storage.log("Server crashed: " .. tostring(err))
end