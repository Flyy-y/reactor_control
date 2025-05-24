local network = dofile("/reactor_control/shared/network.lua")
local protocol = dofile("/reactor_control/shared/protocol.lua")
local battery_api = dofile("/reactor_control/battery/battery_api.lua")

local config = dofile("/reactor_control/battery/config.lua")

local running = true
local lastAlertLevel = nil

local function init()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Battery Controller ===")
    print("Initializing...")
    
    if not battery_api.initialize() then
        error("Failed to initialize battery API")
    end
    
    network.init(nil, {config.server_channel, config.broadcast_channel}, config.privateKey)
    
    print("Controller ready")
    print("Press Q to shutdown")
end

local function checkAlerts(stats)
    local alertLevel = nil
    local alertMessage = nil
    
    if stats.energyPercent <= config.alerts.critical_low then
        alertLevel = protocol.alertLevels.CRITICAL
        alertMessage = "Battery critically low: " .. string.format("%.1f%%", stats.energyPercent)
    elseif stats.energyPercent >= config.alerts.critical_high then
        alertLevel = protocol.alertLevels.CRITICAL
        alertMessage = "Battery critically high: " .. string.format("%.1f%%", stats.energyPercent)
    elseif stats.energyPercent <= config.alerts.low_energy then
        alertLevel = protocol.alertLevels.WARNING
        alertMessage = "Battery low: " .. string.format("%.1f%%", stats.energyPercent)
    elseif stats.energyPercent >= config.alerts.high_energy then
        alertLevel = protocol.alertLevels.WARNING
        alertMessage = "Battery high: " .. string.format("%.1f%%", stats.energyPercent)
    end
    
    if alertLevel and alertLevel ~= lastAlertLevel then
        local alert = network.createMessage(
            protocol.messageTypes.BROADCAST,
            protocol.commands.ALERT,
            protocol.createAlert(
                alertLevel,
                "battery",
                alertMessage,
                stats
            )
        )
        network.broadcast(alert)
        print("[ALERT] " .. alertMessage)
        lastAlertLevel = alertLevel
    elseif not alertLevel then
        lastAlertLevel = nil
    end
end

local function sendBatteryStatus()
    local stats = battery_api.getStats()
    if not stats then
        return
    end
    
    checkAlerts(stats)
    
    local status = protocol.createBatteryStatus(stats)
    local message = network.createMessage(
        protocol.messageTypes.BROADCAST,
        protocol.commands.BATTERY_STATUS,
        status
    )
    
    network.send(config.server_channel, message)
end

local function sendHeartbeat()
    local stats = battery_api.getStats()
    local status = "online"
    
    if stats then
        if stats.energyPercent < 10 then
            status = "low"
        elseif stats.energyPercent > 90 then
            status = "high"
        else
            status = "normal"
        end
    end
    
    local heartbeat = protocol.createHeartbeat(
        "battery",
        1,
        status
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
    
    local stats = battery_api.getStats()
    if not stats then
        return
    end
    
    term.setCursorPos(1, 6)
    term.clearLine()
    print(string.format("Energy: %s / %s", 
        battery_api.getFormattedEnergy(stats.energy),
        battery_api.getFormattedEnergy(stats.maxEnergy)))
    
    term.clearLine()
    print(string.format("Level: %.1f%%", stats.energyPercent))
    
    term.clearLine()
    local netFlow = stats.netFlow
    local flowStr = netFlow >= 0 and "+" or ""
    print(string.format("Net Flow: %s%.0f RF/t", flowStr, netFlow))
    
    term.clearLine()
    print(string.format("Input: %.0f RF/t  Output: %.0f RF/t", 
        stats.lastInput, stats.lastOutput))
    
    term.clearLine()
    if netFlow > 0 then
        local timeToFull = battery_api.getTimeToFull()
        print("Time to full: " .. battery_api.formatTime(timeToFull))
    elseif netFlow < 0 then
        local timeToEmpty = battery_api.getTimeToEmpty()
        print("Time to empty: " .. battery_api.formatTime(timeToEmpty))
    else
        print("Stable - no net flow")
    end
    
    term.clearLine()
    print(string.format("Cells: %d  Providers: %d", 
        stats.cells, stats.providers))
end

local function checkForUpdates()
    if not fs.exists("/reactor_control/updater.lua") then
        return
    end
    
    local updater = dofile("/reactor_control/updater.lua")
    updater.setConfig({
        github_user = "Flyy-y",
        github_repo = "reactor_control",
        branch = "main",
        files = {
            "shared/network.lua",
            "shared/protocol.lua",
            "battery/main.lua",
            "battery/battery_api.lua"
        }
    })
    
    -- This will check and update, then reboot if updates were found
    updater.checkAndUpdate()
end

local function main()
    init()
    
    local statusTimer = os.startTimer(config.update_interval)
    local heartbeatTimer = os.startTimer(config.heartbeat_interval)
    local displayTimer = os.startTimer(config.display.update_interval)
    local updateCheckTimer = os.startTimer(60)  -- Check for updates every 60 seconds
    
    sendBatteryStatus()
    sendHeartbeat()
    
    while running do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "modem_message" then
            network.handleModemMessage(p1, p2, p3, p4, p5)
        elseif event == "timer" then
            if p1 == statusTimer then
                sendBatteryStatus()
                statusTimer = os.startTimer(config.update_interval)
            elseif p1 == heartbeatTimer then
                sendHeartbeat()
                heartbeatTimer = os.startTimer(config.heartbeat_interval)
            elseif p1 == displayTimer then
                displayStatus()
                displayTimer = os.startTimer(config.display.update_interval)
            elseif p1 == updateCheckTimer then
                print("Checking for updates...")
                checkForUpdates()
                updateCheckTimer = os.startTimer(60)
            end
        elseif event == "key" and p1 == keys.q then
            running = false
        end
    end
    
    print("\nShutting down controller...")
end

local success, err = pcall(main)
if not success then
    print("Controller error: " .. tostring(err))
end