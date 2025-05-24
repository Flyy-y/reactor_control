os.loadAPI("/reactor_control/shared/network.lua")
os.loadAPI("/reactor_control/shared/protocol.lua")
os.loadAPI("/reactor_control/reactor_api.lua")

local config = dofile("/reactor_control/reactor/config.lua")

local running = true
local lastEmergencyCheck = 0

local function init()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Reactor Controller ===")
    print("Reactor ID: " .. config.reactor_id)
    print("Initializing...")
    
    if not reactor_api.initialize() then
        error("Failed to initialize reactor API")
    end
    
    network.init(nil, {config.server_channel, config.broadcast_channel}, config.privateKey)
    
    print("Controller ready")
    print("Press Q to shutdown")
end

local function checkEmergency(stats)
    if stats.temperature > config.emergency_shutdown.temperature or
       stats.damage > config.emergency_shutdown.damage or
       stats.wastePercent > config.emergency_shutdown.waste_percent then
        
        print("EMERGENCY SHUTDOWN!")
        print("Temp: " .. stats.temperature .. "K")
        print("Damage: " .. stats.damage .. "%")
        print("Waste: " .. stats.wastePercent .. "%")
        
        reactor_api.scram()
        
        local alert = network.createMessage(
            protocol.messageTypes.BROADCAST,
            protocol.commands.ALERT,
            protocol.createAlert(
                protocol.alertLevels.EMERGENCY,
                "reactor_" .. config.reactor_id,
                "Emergency shutdown triggered",
                stats
            )
        )
        network.broadcast(alert)
        
        return true
    end
    return false
end

local function sendReactorStatus()
    local stats = reactor_api.getStats()
    if not stats then
        return
    end
    
    if os.epoch("utc") - lastEmergencyCheck > 1000 then
        checkEmergency(stats)
        lastEmergencyCheck = os.epoch("utc")
    end
    
    local status = protocol.createReactorStatus(config.reactor_id, stats)
    local message = network.createMessage(
        protocol.messageTypes.BROADCAST,
        protocol.commands.REACTOR_STATUS,
        status
    )
    
    network.send(config.server_channel, message)
end

local function handleReactorControl(message)
    local data = message.data
    
    if data.reactor_id ~= config.reactor_id then
        return
    end
    
    local success = false
    local result = "Unknown action"
    
    if data.action == protocol.reactorActions.ACTIVATE then
        success = reactor_api.activate()
        result = success and "Reactor activated" or "Failed to activate"
    elseif data.action == protocol.reactorActions.SCRAM then
        success = reactor_api.scram()
        result = success and "Reactor scrammed" or "Failed to scram"
    elseif data.action == protocol.reactorActions.SET_BURN_RATE then
        success = reactor_api.setBurnRate(data.value or 0)
        result = success and "Burn rate set to " .. (data.value or 0) or "Failed to set burn rate"
    elseif data.action == "adjust_burn" then
        success = reactor_api.setBurnRate(data.value or 0)
        result = success and "Burn rate adjusted to " .. (data.value or 0) or "Failed to adjust burn rate"
    end
    
    print("[Control] " .. result)
    
    network.respond(message, {
        success = success,
        result = result
    }, success and "ok" or "error")
end

local function sendHeartbeat()
    local heartbeat = protocol.createHeartbeat(
        "reactor",
        config.reactor_id,
        reactor_api.isActive() and "active" or "idle"
    )
    
    local message = network.createMessage(
        protocol.messageTypes.BROADCAST,
        protocol.commands.HEARTBEAT,
        heartbeat
    )
    
    network.send(config.server_channel, message)
end

local function displayStatus()
    if not config.display.enabled then
        return
    end
    
    local stats = reactor_api.getStats()
    if not stats then
        return
    end
    
    term.setCursorPos(1, 6)
    term.clearLine()
    print(string.format("Status: %s", stats.active and "ACTIVE" or "OFFLINE"))
    
    term.clearLine()
    print(string.format("Temp: %.1fK  Burn: %.1f/%.1f mB/t", 
        stats.temperature, stats.actualBurnRate, stats.burnRate))
    
    term.clearLine()
    print(string.format("Fuel: %.1f%%  Waste: %.1f%%", 
        stats.fuelPercent, stats.wastePercent))
    
    term.clearLine()
    print(string.format("Coolant: %.1f%%  Heated: %.1f%%", 
        stats.coolantPercent, stats.heatedCoolantPercent))
    
    term.clearLine()
    print(string.format("Damage: %.2f%%  Efficiency: %.1f%%", 
        stats.damage, stats.boilEfficiency))
end

local function handleDiscoverReactors(message, channel)
    -- Respond with our reactor info
    local response = network.createMessage(
        protocol.messageTypes.RESPONSE,
        protocol.commands.REACTOR_INFO,
        {reactor_id = config.reactor_id}
    )
    network.send(channel, response)
end

local function main()
    init()
    
    network.on(protocol.commands.REACTOR_CONTROL, handleReactorControl)
    network.on(protocol.commands.DISCOVER_REACTORS, handleDiscoverReactors)
    
    local statusTimer = os.startTimer(config.update_interval)
    local heartbeatTimer = os.startTimer(config.heartbeat_interval)
    local displayTimer = os.startTimer(config.display.update_interval)
    
    sendReactorStatus()
    sendHeartbeat()
    
    while running do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "modem_message" then
            network.handleModemMessage(p1, p2, p3, p4, p5)
        elseif event == "timer" then
            if p1 == statusTimer then
                sendReactorStatus()
                statusTimer = os.startTimer(config.update_interval)
            elseif p1 == heartbeatTimer then
                sendHeartbeat()
                heartbeatTimer = os.startTimer(config.heartbeat_interval)
            elseif p1 == displayTimer then
                displayStatus()
                displayTimer = os.startTimer(config.display.update_interval)
            end
        elseif event == "key" then
            if p1 == keys.q then
                running = false
            elseif p1 == keys.e then
                print("\nEmergency shutdown!")
                reactor_api.scram()
            end
        end
    end
    
    print("\nShutting down controller...")
    reactor_api.scram()
end

local success, err = pcall(main)
if not success then
    print("Controller error: " .. tostring(err))
    reactor_api.scram()
end