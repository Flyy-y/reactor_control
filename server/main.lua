-- Load required modules using dofile
local network = dofile("/reactor_control/shared/network.lua")
local protocol = dofile("/reactor_control/shared/protocol.lua")
local rules = dofile("/reactor_control/server/rules.lua")
local storage = dofile("/reactor_control/server/storage.lua")

local config = dofile("/reactor_control/server/config.lua")

local componentStatus = {}
local manualScramReactors = {}  -- Track manually scrammed reactors

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
    
    network.init(nil, channels)
    storage.init(config)
    
    storage.log("Server started")
    print("Server ready on channel " .. config.modem_channel)
end

local function handleReactorStatus(message, channel)
    local data = message.data
    rules.updateReactorState(data.reactor_id, data)
    
    componentStatus["reactor_" .. data.reactor_id] = os.epoch("utc")
    
    local decision = rules.getReactorDecision(data.reactor_id, config)
    
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
    
    componentStatus["battery"] = os.epoch("utc")
end

local function handleDisplayRequest(message, channel)
    local requestType = message.data.type
    local response = nil
    
    if requestType == "system_status" then
        response = rules.getSystemStatus()
        -- Always ensure we have a response, even if components are not responding
        if not response then
            response = {
                reactors = {},
                battery = nil,
                timestamp = os.epoch("utc")
            }
        end
    elseif requestType == "alerts" then
        -- Return current active alerts from rules
        local alerts = rules.checkAlerts(config)
        response = alerts
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

local function optimizeBurnRates()
    if not config.auto_control.enabled then return end
    
    local status = rules.getSystemStatus()
    if not status.battery then return end
    
    -- Check if battery is offline for too long
    local timeSinceUpdate = (os.epoch("utc") - status.battery.lastUpdate) / 1000
    if timeSinceUpdate > 30 then
        -- Battery offline - don't activate any reactors
        return
    end
    
    local batteryPercent = status.battery.percent_full
    
    for reactorId, reactor in pairs(status.reactors or {}) do
        -- Skip manually scrammed reactors
        if not manualScramReactors[reactorId] then
            print(string.format("Debug Reactor %d - Active: %s, Battery: %.1f%%", 
                reactorId, reactor.active and "Yes" or "No", batteryPercent))
            
            -- Simple on/off control based on battery level
            if batteryPercent <= config.auto_control.battery_low and not reactor.active then
                -- Battery low, check if it's safe to turn reactor on
                local safe, reason = rules.checkSafetyConditions(reactorId, config)
                
                if safe then
                    -- All safety conditions met, activate reactor
                    local activateMsg = network.createMessage(
                        protocol.messageTypes.REQUEST,
                        protocol.commands.REACTOR_CONTROL,
                        {
                            reactor_id = reactorId,
                            action = "activate"
                        }
                    )
                    
                    local reactorChannel = config.reactor_channels[reactorId]
                    if reactorChannel then
                        network.send(reactorChannel, activateMsg)
                        storage.log("Auto-activated reactor " .. reactorId .. " (battery " .. string.format("%.1f%%", batteryPercent) .. ")")
                        manualScramReactors[reactorId] = nil -- Clear manual scram flag
                    end
                else
                    -- Safety conditions not met, log why we can't activate
                    storage.log("Cannot auto-activate reactor " .. reactorId .. ": " .. reason)
                end
                
            elseif batteryPercent >= config.auto_control.battery_high and reactor.active then
                -- Battery high, turn reactor off
                local scramMsg = network.createMessage(
                    protocol.messageTypes.REQUEST,
                    protocol.commands.REACTOR_CONTROL,
                    {
                        reactor_id = reactorId,
                        action = "scram"
                    }
                )
                
                local reactorChannel = config.reactor_channels[reactorId]
                if reactorChannel then
                    network.send(reactorChannel, scramMsg)
                    storage.log("Auto-scrammed reactor " .. reactorId .. " (battery " .. string.format("%.1f%%", batteryPercent) .. ")")
                end
            end
        end
    end
end

local batteryPingAttempted = {}  -- Track when we last tried to ping battery

local function checkAndSendAlerts()
    local alerts = rules.checkAlerts(config)
    local clearedAlerts = rules.getClearedAlerts()  -- Get alerts that were cleared
    
    -- Check if battery is not responding and needs a ping
    local status = rules.getSystemStatus()
    if status.battery then
        local timeSinceUpdate = (os.epoch("utc") - status.battery.lastUpdate) / 1000
        local lastPingTime = batteryPingAttempted.last or 0
        local timeSincePing = (os.epoch("utc") - lastPingTime) / 1000
        
        -- If battery hasn't responded in 10+ seconds and we haven't pinged in the last 30 seconds
        if timeSinceUpdate > 10 and timeSincePing > 30 then
            storage.log("Battery not responding for " .. math.floor(timeSinceUpdate) .. "s - sending wake-up ping")
            
            local batteryPingMsg = network.createMessage(
                protocol.messageTypes.REQUEST,
                protocol.commands.HEARTBEAT,
                {
                    type = "ping",
                    timestamp = os.epoch("utc")
                }
            )
            network.send(config.battery_channel, batteryPingMsg)
            
            batteryPingAttempted.last = os.epoch("utc")
        end
    end
    
    -- Log cleared alerts
    for _, alert in ipairs(clearedAlerts) do
        storage.log("ALERT CLEARED [" .. alert.level .. "] " .. alert.source .. ": " .. alert.message)
    end
    
    for _, alert in ipairs(alerts) do
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

local function pingComponents()
    -- Send ping to all known reactors to maintain contact
    local status = rules.getSystemStatus()
    for reactorId, reactor in pairs(status.reactors or {}) do
        local pingMsg = network.createMessage(
            protocol.messageTypes.REQUEST,
            protocol.commands.HEARTBEAT,
            {
                type = "ping",
                timestamp = os.epoch("utc")
            }
        )
        
        local reactorChannel = config.reactor_channels[reactorId]
        if reactorChannel then
            network.send(reactorChannel, pingMsg)
        end
    end
    
    -- Also ping the battery controller
    if status.battery then
        local batteryPingMsg = network.createMessage(
            protocol.messageTypes.REQUEST,
            protocol.commands.HEARTBEAT,
            {
                type = "ping",
                timestamp = os.epoch("utc")
            }
        )
        network.send(config.battery_channel, batteryPingMsg)
    end
    
    -- Ping display controllers too
    for _, displayChannel in ipairs(config.display_channels) do
        local displayPingMsg = network.createMessage(
            protocol.messageTypes.REQUEST,
            protocol.commands.HEARTBEAT,
            {
                type = "ping",
                timestamp = os.epoch("utc")
            }
        )
        network.send(displayChannel, displayPingMsg)
    end
end

local function periodicTasks()
    checkAndSendAlerts()
    optimizeBurnRates()  -- Add burn rate optimization
    pingComponents()  -- Ping reactors and battery to maintain contact
    
    local health = rules.checkComponentHealth(config)
    for component, isHealthy in pairs(health.reactors) do
        if not isHealthy then
            storage.log("WARNING: Reactor " .. component .. " not responding")
        end
    end
    
    if not health.battery then
        storage.log("WARNING: Battery controller not responding")
    end
    
    -- Data saving removed - no longer persisting history
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

local function handleReactorControl(message, channel)
    -- Track manual scrams
    if message.data.action == "scram" then
        manualScramReactors[message.data.reactor_id] = true
        storage.log("Manual SCRAM for reactor " .. message.data.reactor_id)
    elseif message.data.action == "activate" then
        manualScramReactors[message.data.reactor_id] = nil
        storage.log("Manual activation for reactor " .. message.data.reactor_id)
    end
    
    -- Forward control message to appropriate reactor
    local reactorChannel = config.reactor_channels[message.data.reactor_id]
    if reactorChannel then
        network.send(reactorChannel, message)
        storage.log("Forwarded control to reactor " .. message.data.reactor_id)
    end
end

local function setupHandlers()
    network.on(protocol.commands.REACTOR_STATUS, handleReactorStatus)
    network.on(protocol.commands.BATTERY_STATUS, handleBatteryStatus)
    network.on(protocol.commands.DISPLAY_REQUEST, handleDisplayRequest)
    network.on(protocol.commands.HEARTBEAT, handleHeartbeat)
    network.on(protocol.commands.DISCOVER_REACTORS, handleDiscoverReactors)
    network.on(protocol.commands.REACTOR_CONTROL, handleReactorControl)
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
            break
        end
    end
end

local success, err = pcall(main)
if not success then
    print("Server error: " .. tostring(err))
    storage.log("Server crashed: " .. tostring(err))
end