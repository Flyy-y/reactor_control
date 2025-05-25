local network = dofile("/reactor_control/shared/network.lua")
local protocol = dofile("/reactor_control/shared/protocol.lua")
local battery_api = dofile("/reactor_control/battery/battery_api.lua")

local config = dofile("/reactor_control/battery/config.lua")

local running = true
local lastAlertLevel = nil
local lastSuccessfulSend = os.epoch("utc")
local failureCount = 0

local function init()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Battery Controller ===")
    print("Initializing...")
    
    if not battery_api.initialize() then
        error("Failed to initialize battery API")
    end
    
    network.init(nil, {config.server_channel, config.broadcast_channel})
    
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
    local success, stats = pcall(battery_api.getStats)
    if not success then
        print("Error getting battery stats: " .. tostring(stats))
        return
    end
    
    if not stats then
        print("Failed to get battery stats - no data returned")
        return
    end
    
    local alertSuccess, alertError = pcall(checkAlerts, stats)
    if not alertSuccess then
        print("Error checking alerts: " .. tostring(alertError))
    end
    
    local protocolSuccess, status = pcall(protocol.createBatteryStatus, stats)
    if not protocolSuccess then
        print("Error creating battery status: " .. tostring(status))
        return
    end
    
    local message = network.createMessage(
        protocol.messageTypes.BROADCAST,
        protocol.commands.BATTERY_STATUS,
        status
    )
    
    local sendSuccess, sendError = pcall(network.send, config.server_channel, message)
    if sendSuccess then
        local time = os.date("%H:%M:%S")
        print(string.format("[%s] Sent battery status: %.1f%%", time, stats.energyPercent))
        lastSuccessfulSend = os.epoch("utc")
        failureCount = 0
        
        -- Clear any error messages and show success
        term.setCursorPos(1, 10)
        term.clearLine()
        term.setTextColor(colors.green)
        print("✓ Status sent successfully")
        term.setTextColor(colors.white)
        term.clearLine()
        term.clearLine()
        term.clearLine()
    else
        local time = os.date("%H:%M:%S")
        print(string.format("[%s] Error sending battery status: %s", time, tostring(sendError)))
        failureCount = failureCount + 1
        
        -- Display error status on screen
        term.setCursorPos(1, 10)
        term.setTextColor(colors.red)
        term.clearLine()
        print("!!! FAILED TO SEND STATUS !!!")
        term.clearLine()
        print("Error: " .. string.sub(tostring(sendError), 1, 40))
        term.clearLine()
        print("Failure count: " .. failureCount)
        term.setTextColor(colors.white)
        
        -- If we've failed too many times, try to reinitialize
        if failureCount >= 5 then
            term.setCursorPos(1, 14)
            term.setTextColor(colors.orange)
            print("Too many failures, attempting to reinitialize...")
            term.setTextColor(colors.white)
            
            local initSuccess, initError = pcall(battery_api.initialize)
            if initSuccess then
                print("Battery API reinitialized successfully")
                failureCount = 0
            else
                term.setTextColor(colors.red)
                print("Failed to reinitialize battery API: " .. tostring(initError))
                term.setTextColor(colors.white)
            end
        end
    end
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

local function handlePing(message, channel)
    -- Acknowledge the ping and send battery status
    local time = os.date("%H:%M:%S")
    print(string.format("[%s] Received server ping", time))
    
    -- Send battery status in response to ping
    sendBatteryStatus()
end

local function main()
    init()
    
    network.on(protocol.commands.HEARTBEAT, handlePing)
    
    local statusTimer = os.startTimer(config.update_interval)
    local heartbeatTimer = os.startTimer(config.heartbeat_interval)
    local displayTimer = os.startTimer(config.display.update_interval)
    local watchdogTimer = os.startTimer(30)  -- Check every 30 seconds
    
    sendBatteryStatus()
    sendHeartbeat()
    
    while running do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "modem_message" then
            network.handleModemMessage(p1, p2, p3, p4, p5)
        elseif event == "timer" then
            if p1 == statusTimer then
                local success, error = pcall(sendBatteryStatus)
                if not success then
                    print("Error in sendBatteryStatus: " .. tostring(error))
                end
                statusTimer = os.startTimer(config.update_interval)
            elseif p1 == heartbeatTimer then
                local success, error = pcall(sendHeartbeat)
                if not success then
                    print("Error in sendHeartbeat: " .. tostring(error))
                end
                heartbeatTimer = os.startTimer(config.heartbeat_interval)
            elseif p1 == displayTimer then
                local success, error = pcall(displayStatus)
                if not success then
                    print("Error in displayStatus: " .. tostring(error))
                end
                displayTimer = os.startTimer(config.display.update_interval)
            elseif p1 == watchdogTimer then
                -- Check if we haven't sent status in too long
                local timeSinceLastSend = (os.epoch("utc") - lastSuccessfulSend) / 1000
                if timeSinceLastSend > 60 then  -- 60 seconds without successful send
                    local time = os.date("%H:%M:%S")
                    print(string.format("[%s] WATCHDOG: No successful status sent in %d seconds", time, math.floor(timeSinceLastSend)))
                    print(string.format("[%s] Attempting recovery...", time))
                    
                    -- Display watchdog alert on screen
                    term.setCursorPos(1, 16)
                    term.setTextColor(colors.red)
                    term.clearLine()
                    print("!!! WATCHDOG ALERT !!!")
                    term.clearLine()
                    print("No successful send for " .. math.floor(timeSinceLastSend) .. " seconds")
                    term.setTextColor(colors.white)
                    
                    -- Try to reinitialize everything
                    local initSuccess, initError = pcall(battery_api.initialize)
                    if initSuccess then
                        print("Battery API reinitialized")
                        lastSuccessfulSend = os.epoch("utc")
                        failureCount = 0
                    else
                        print("Recovery failed: " .. tostring(initError))
                    end
                end
                watchdogTimer = os.startTimer(30)
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