local network = dofile("/reactor_control/shared/network.lua")
local protocol = dofile("/reactor_control/shared/protocol.lua")

local config = dofile("/reactor_control/reactor/config.lua")

local running = true
local lastEmergencyCheck = 0
local lastServerContact = os.epoch("utc")  -- Track last server communication

-- Reactor API variables
local reactor = nil
local side = nil

-- Reactor API functions
local function findReactor()
    local peripherals = peripheral.getNames()
    
    for _, name in ipairs(peripherals) do
        local pType = peripheral.getType(name)
        if pType == "fissionReactor" or pType == "fissionReactorLogicAdapter" then
            reactor = peripheral.wrap(name)
            side = name
            print("Found fission reactor on: " .. name)
            return true
        end
    end
    
    return false
end

local function initializeReactor()
    if not findReactor() then
        error("No fission reactor found! Please connect a Mekanism Fission Reactor")
    end
    
    return true
end

local function isActive()
    if not reactor then return false end
    return reactor.getStatus()
end

local function activate()
    if not reactor then return false end
    if isActive() then return true end
    reactor.activate()
    return true
end

local function scram()
    if not reactor then return false end
    if not isActive() then return true end  -- Already scrammed
    reactor.scram()
    return true
end

local function getBurnRate()
    if not reactor then return 0 end
    return reactor.getBurnRate()
end

local function getActualBurnRate()
    if not reactor then return 0 end
    return reactor.getActualBurnRate()
end

local function setBurnRate(rate)
    if not reactor then return false end
    reactor.setBurnRate(rate)
    return true
end

local function getMaxBurnRate()
    if not reactor then return 0 end
    return reactor.getMaxBurnRate()
end

local function getTemperature()
    if not reactor then return 0 end
    return reactor.getTemperature()
end

local function getDamagePercent()
    if not reactor then return 0 end
    return reactor.getDamagePercent()
end

local function getBoilEfficiency()
    if not reactor then return 0 end
    return reactor.getBoilEfficiency()
end

local function getHeatCapacity()
    if not reactor then return 0 end
    return reactor.getHeatCapacity()
end

local function getFuelCapacity()
    if not reactor then return 0 end
    if reactor.getFuelCapacity then
        return reactor.getFuelCapacity()
    end
    return 0
end

local function getFuelAmount()
    if not reactor then return 0 end
    if reactor.getFuel then
        local fuel = reactor.getFuel()
        if fuel and fuel.amount then
            return fuel.amount
        end
    end
    return 0
end

local function getFuelPercent()
    if not reactor then return 0 end
    local capacity = getFuelCapacity()
    local amount = getFuelAmount()
    if capacity == 0 then return 0 end
    return (amount / capacity) * 100
end

local function getWasteCapacity()
    if not reactor then return 0 end
    if reactor.getWasteCapacity then
        return reactor.getWasteCapacity()
    end
    return 0
end

local function getWasteAmount()
    if not reactor then return 0 end
    if reactor.getWaste then
        local waste = reactor.getWaste()
        if waste and waste.amount then
            return waste.amount
        end
    end
    return 0
end

local function getWastePercent()
    if not reactor then return 0 end
    local capacity = getWasteCapacity()
    local amount = getWasteAmount()
    if capacity == 0 then return 0 end
    return (amount / capacity) * 100
end

local function getCoolantCapacity()
    if not reactor then return 0 end
    if reactor.getCoolantCapacity then
        return reactor.getCoolantCapacity()
    end
    return 0
end

local function getCoolantAmount()
    if not reactor then return 0 end
    if reactor.getCoolant then
        local coolant = reactor.getCoolant()
        if coolant and coolant.amount then
            return coolant.amount
        end
    end
    return 0
end

local function getCoolantPercent()
    if not reactor then return 0 end
    local capacity = getCoolantCapacity()
    local amount = getCoolantAmount()
    if capacity == 0 then return 0 end
    return (amount / capacity) * 100
end

local function getHeatedCoolantCapacity()
    if not reactor then return 0 end
    if reactor.getHeatedCoolantCapacity then
        return reactor.getHeatedCoolantCapacity()
    end
    return 0
end

local function getHeatedCoolantAmount()
    if not reactor then return 0 end
    if reactor.getHeatedCoolant then
        local heatedCoolant = reactor.getHeatedCoolant()
        if heatedCoolant and heatedCoolant.amount then
            return heatedCoolant.amount
        end
    end
    return 0
end

local function getHeatedCoolantPercent()
    if not reactor then return 0 end
    local capacity = getHeatedCoolantCapacity()
    local amount = getHeatedCoolantAmount()
    if capacity == 0 then return 0 end
    return (amount / capacity) * 100
end

local function getStats()
    if not reactor then return nil end
    
    return {
        active = isActive(),
        temperature = getTemperature(),
        damage = getDamagePercent(),
        burnRate = getBurnRate(),
        actualBurnRate = getActualBurnRate(),
        maxBurnRate = getMaxBurnRate(),
        boilEfficiency = getBoilEfficiency(),
        heatCapacity = getHeatCapacity(),
        fuelAmount = getFuelAmount(),
        fuelCapacity = getFuelCapacity(),
        fuelPercent = getFuelPercent(),
        wasteAmount = getWasteAmount(),
        wasteCapacity = getWasteCapacity(),
        wastePercent = getWastePercent(),
        coolantAmount = getCoolantAmount(),
        coolantCapacity = getCoolantCapacity(),
        coolantPercent = getCoolantPercent(),
        heatedCoolantAmount = getHeatedCoolantAmount(),
        heatedCoolantCapacity = getHeatedCoolantCapacity(),
        heatedCoolantPercent = getHeatedCoolantPercent()
    }
end

-- Main reactor controller functions
local function init()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Reactor Controller ===")
    print("Reactor ID: " .. config.reactor_id)
    print("Initializing...")
    
    if not initializeReactor() then
        error("Failed to initialize reactor")
    end
    
    -- Safety: SCRAM reactor on startup in case controller crashed while reactor was running
    print("Safety SCRAM on startup...")
    scram()
    
    network.init(nil, {config.server_channel, config.broadcast_channel})
    
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
        
        scram()
        
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

local function checkServerTimeout()
    local timeSinceContact = (os.epoch("utc") - lastServerContact) / 1000  -- Convert to seconds
    
    if timeSinceContact > 15 and isActive() then
        print("\nWARNING: No server contact for " .. math.floor(timeSinceContact) .. " seconds!")
        print("SAFETY SHUTDOWN - Scraming reactor!")
        scram()
        
        -- Send alert
        local alert = network.createMessage(
            protocol.messageTypes.BROADCAST,
            protocol.commands.ALERT,
            protocol.createAlert(
                protocol.alertLevels.EMERGENCY,
                "reactor_" .. config.reactor_id,
                "Safety shutdown - lost server connection",
                {timeout_seconds = timeSinceContact}
            )
        )
        network.broadcast(alert)
    end
end

local function sendReactorStatus()
    local stats = getStats()
    if not stats then
        return
    end
    
    if os.epoch("utc") - lastEmergencyCheck > 1000 then
        checkEmergency(stats)
        checkServerTimeout()  -- Check for server timeout
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
    
    -- Update last server contact time
    lastServerContact = os.epoch("utc")
    
    local success = false
    local result = "Unknown action"
    
    if data.action == protocol.reactorActions.ACTIVATE then
        success = activate()
        result = success and "Reactor activated" or "Failed to activate"
    elseif data.action == protocol.reactorActions.SCRAM then
        success = scram()
        result = success and "Reactor scrammed" or "Failed to scram"
    elseif data.action == protocol.reactorActions.SET_BURN_RATE then
        success = setBurnRate(data.value or 0)
        result = success and "Burn rate set to " .. (data.value or 0) or "Failed to set burn rate"
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
        isActive() and "active" or "idle"
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
    
    local stats = getStats()
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
    print(string.format("Fuel: %.1f%% (%d/%d)", 
        stats.fuelPercent, stats.fuelAmount, stats.fuelCapacity))
    
    term.clearLine()
    print(string.format("Waste: %.1f%% (%d/%d)", 
        stats.wastePercent, stats.wasteAmount, stats.wasteCapacity))
    
    term.clearLine()
    print(string.format("Coolant: %.1f%% (%d/%d)", 
        stats.coolantPercent, stats.coolantAmount, stats.coolantCapacity))
    
    term.clearLine()
    print(string.format("Damage: %.2f%%  Efficiency: %.1f%%", 
        stats.damage, stats.boilEfficiency))
end

local function handleDiscoverReactors(message, channel)
    -- Update last server contact if from server
    if channel == config.server_channel then
        lastServerContact = os.epoch("utc")
    end
    
    -- Respond with our reactor info
    local response = network.createMessage(
        protocol.messageTypes.RESPONSE,
        protocol.commands.REACTOR_INFO,
        {reactor_id = config.reactor_id}
    )
    network.send(channel, response)
end

local function handlePing(message, channel)
    -- Update last server contact time when receiving ping
    lastServerContact = os.epoch("utc")
    print("Received server ping")
end

-- Ensure reactor is shut down on any exit
local function safeShutdown(reason)
    print("\nSAFETY: Ensuring reactor is shut down...")
    print("Reason: " .. (reason or "Unknown"))
    
    -- Try multiple times to ensure reactor is off
    for i = 1, 3 do
        local success = scram()
        if success then
            print("Reactor SCRAM successful (attempt " .. i .. ")")
            break
        else
            print("SCRAM attempt " .. i .. " failed, retrying...")
            os.sleep(0.5)
        end
    end
    
    -- Final check
    if isActive() then
        print("WARNING: Reactor may still be active!")
        print("MANUAL INTERVENTION REQUIRED!")
    else
        print("Reactor confirmed OFF")
    end
end

local function main()
    init()
    
    network.on(protocol.commands.REACTOR_CONTROL, handleReactorControl)
    network.on(protocol.commands.DISCOVER_REACTORS, handleDiscoverReactors)
    network.on(protocol.commands.HEARTBEAT, handlePing)
    
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
                scram()
            end
        elseif event == "terminate" then
            -- Handle Ctrl+T
            running = false
            print("\nTerminate signal received!")
        end
    end
    
    safeShutdown("Normal shutdown")
end

-- Wrap entire program to catch ALL exits
local function safeMain()
    local success, err = pcall(main)
    if not success then
        print("Controller error: " .. tostring(err))
        safeShutdown("Error: " .. tostring(err))
    end
end

-- Final safety wrapper
local finalSuccess, finalErr = pcall(safeMain)
if not finalSuccess then
    print("CRITICAL ERROR: " .. tostring(finalErr))
    -- Last ditch effort to shut down reactor
    if reactor then
        pcall(function() reactor.scram() end)
    end
end