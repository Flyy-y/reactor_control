-- Load required modules using dofile
local network = dofile("/reactor_control/shared/network.lua")
local protocol = dofile("/reactor_control/shared/protocol.lua")
local ui = dofile("/reactor_control/display/ui.lua")

local config = dofile("/reactor_control/display/config.lua")

local running = true
local systemStatus = nil
local alerts = {}
local temperatureHistory = {}
local batteryHistory = {}
local reactorButtons = {}
local pendingActions = {}  -- Track pending reactor state changes

local function init()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Display Controller ===")
    print("Display ID: " .. config.display_id)
    print("Initializing...")
    
    ui.init(config)
    network.init(nil, {config.server_channel, config.listen_channel})
    
    print("Display ready")
    print("Press Q to shutdown")
end

local function requestSystemStatus()
    local message = network.createMessage(
        protocol.messageTypes.REQUEST,
        protocol.commands.DISPLAY_REQUEST,
        {
            type = "system_status"
        }
    )
    
    local success, response = network.request(config.server_channel, 
        protocol.commands.DISPLAY_REQUEST, 
        {type = "system_status"}, 
        config.request_timeout)
    
    if success and response.data then
        systemStatus = response.data
        print("Got system status update")
        -- Clear pending actions as we have fresh data
        pendingActions = {}
    else
        print("Failed to get system status: " .. tostring(response))
        -- Don't clear systemStatus, keep showing last known data
        return
    end
    
    if systemStatus then
        for reactorId, reactor in pairs(systemStatus.reactors or {}) do
            if not temperatureHistory[reactorId] then
                temperatureHistory[reactorId] = {}
            end
            table.insert(temperatureHistory[reactorId], reactor.temperature or 0)
            
            while #temperatureHistory[reactorId] > config.display.graph_history do
                table.remove(temperatureHistory[reactorId], 1)
            end
        end
        
        if systemStatus.battery then
            table.insert(batteryHistory, systemStatus.battery.percent_full or 0)
            
            while #batteryHistory > config.display.graph_history do
                table.remove(batteryHistory, 1)
            end
        end
    end
end

local function requestAlerts()
    local success, response = network.request(config.server_channel, 
        protocol.commands.DISPLAY_REQUEST, 
        {
            type = "alerts",
            count = config.display.max_alerts
        }, 
        config.request_timeout)
    
    if success and response.data then
        alerts = response.data
    end
end

local function handleAlert(message)
    table.insert(alerts, message.data)
    
    while #alerts > config.display.max_alerts * 2 do
        table.remove(alerts, 1)
    end
end

local function handlePing(message, channel)
    -- Acknowledge server ping
    print("Received server ping")
end

local function sendReactorControl(reactorId, action, value)
    local controlData = {
        reactor_id = reactorId,
        action = action,
        value = value
    }
    
    local message = network.createMessage(
        protocol.messageTypes.REQUEST,
        protocol.commands.REACTOR_CONTROL,
        controlData
    )
    
    network.send(config.server_channel, message)
end

local function drawDisplay()
    ui.clear()
    ui.drawHeader("REACTOR CONTROL SYSTEM")
    
    local w, h = ui.getSize()
    
    reactorButtons = {}
    
    if systemStatus then
        local reactorX = 2
        local reactorY = 3
        local reactorCount = 0
        
        -- Draw reactors (up to 2 side by side)
        for reactorId, reactor in pairs(systemStatus.reactors or {}) do
            local pendingAction = pendingActions[reactorId]
            local buttons = ui.drawReactorStatus(reactorX, reactorY, reactorId, reactor, pendingAction)
            table.insert(reactorButtons, buttons)
            
            reactorX = math.floor(w / 2) + 2
            reactorCount = reactorCount + 1
            
            if reactorCount >= 2 then
                break -- Only show 2 reactors on large display
            end
        end
        
        -- Battery position
        local batteryY = math.floor(h / 2) + 2
        ui.drawBatteryStatus(2, batteryY, systemStatus.battery)
        
        
        -- Alerts on the right side if space allows
        if w > 80 then
            ui.drawAlerts(w - 30, 3, alerts)
        end
    else
        ui.getMonitor().setCursorPos(2, 3)
        ui.getMonitor().write("Waiting for data...")
    end
    
    -- Show update time at bottom
    ui.getMonitor().setCursorPos(1, h)
    ui.getMonitor().setTextColor(colors.gray)
    ui.getMonitor().write("Updated: " .. ui.formatTime(os.epoch("utc")))
    ui.getMonitor().setTextColor(colors.white)
end


local function main()
    init()
    
    network.on(protocol.commands.ALERT, handleAlert)
    network.on(protocol.commands.HEARTBEAT, handlePing)
    
    local updateTimer = os.startTimer(config.update_interval)
    local requestTimer = os.startTimer(0.1)
    
    while running do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "modem_message" then
            network.handleModemMessage(p1, p2, p3, p4, p5)
        elseif event == "timer" then
            if p1 == updateTimer then
                drawDisplay()
                updateTimer = os.startTimer(config.update_interval)
            elseif p1 == requestTimer then
                requestSystemStatus()
                requestAlerts()
                requestTimer = os.startTimer(config.update_interval)
            end
        elseif event == "key" and p1 == keys.q then
            running = false
        elseif event == "monitor_touch" then
            local x, y = p2, p3
            
            -- Check reactor buttons
            for _, buttons in ipairs(reactorButtons) do
                if ui.isButtonClicked(buttons.toggleButton, x, y) then
                    if buttons.active then
                        sendReactorControl(buttons.reactorId, "scram")
                        pendingActions[buttons.reactorId] = "STOPPING"
                    else
                        sendReactorControl(buttons.reactorId, "activate")
                        pendingActions[buttons.reactorId] = "STARTING"
                    end
                    -- Immediately redraw to show pending status
                    drawDisplay()
                elseif buttons.decreaseBurnButton and ui.isButtonClicked(buttons.decreaseBurnButton, x, y) then
                    -- Decrease burn rate by 1 mB/t
                    local newBurnRate = math.max(0, (buttons.burnRate or 0) - 1)
                    sendReactorControl(buttons.reactorId, "set_burn_rate", newBurnRate)
                elseif buttons.increaseBurnButton and ui.isButtonClicked(buttons.increaseBurnButton, x, y) then
                    -- Increase burn rate by 1 mB/t (max 100)
                    local newBurnRate = math.min(100, (buttons.burnRate or 0) + 1)
                    sendReactorControl(buttons.reactorId, "set_burn_rate", newBurnRate)
                end
            end
            
            
            -- Request immediate update without blocking
            requestTimer = os.startTimer(0.1)
        end
    end
    
    print("\nShutting down display...")
    ui.clear()
end

local success, err = pcall(main)
if not success then
    print("Display error: " .. tostring(err))
end