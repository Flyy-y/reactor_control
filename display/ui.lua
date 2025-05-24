local ui = {}

local monitor = nil
local width, height = 0, 0
local config = nil

-- Windows for different sections
local headerWindow = nil
local reactorWindow = nil
local batteryWindow = nil
local alertWindow = nil

function ui.init(displayConfig)
    config = displayConfig
    
    if config.monitor.side == "auto" then
        monitor = peripheral.find("monitor")
    else
        monitor = peripheral.wrap(config.monitor.side)
    end
    
    if not monitor then
        error("No monitor found!")
    end
    
    monitor.setTextScale(config.monitor.text_scale)
    monitor.setBackgroundColor(config.colors.background)
    monitor.clear()
    
    width, height = monitor.getSize()
    
    -- Create windows for 8x4 monitor layout
    -- Header takes top row
    headerWindow = window.create(monitor, 1, 1, width, 1)
    
    -- Main content area (remaining 3 rows)
    -- Reactor status on left (4 columns)
    reactorWindow = window.create(monitor, 1, 2, 4, 3)
    
    -- Battery and alerts on right (4 columns)
    batteryWindow = window.create(monitor, 5, 2, 4, 1)
    alertWindow = window.create(monitor, 5, 3, 4, 2)
    
    return true
end

function ui.clear()
    monitor.setBackgroundColor(config.colors.background)
    monitor.clear()
end

function ui.drawHeader(title)
    headerWindow.setBackgroundColor(config.colors.header)
    headerWindow.setTextColor(config.colors.background)
    headerWindow.clear()
    
    -- Center the title in 8 character width
    local padding = math.floor((8 - #title) / 2)
    if #title > 8 then
        title = string.sub(title, 1, 8)
    end
    headerWindow.setCursorPos(math.max(1, padding + 1), 1)
    headerWindow.write(title)
    
    headerWindow.setBackgroundColor(config.colors.background)
    headerWindow.setTextColor(config.colors.text)
end

function ui.drawReactorStatus(x, y, reactorId, reactor)
    -- Use the reactor window
    reactorWindow.setBackgroundColor(config.colors.background)
    reactorWindow.setTextColor(config.colors.text)
    reactorWindow.clear()
    
    -- Reactor ID and status (row 1)
    reactorWindow.setCursorPos(1, 1)
    reactorWindow.setTextColor(config.colors.header)
    reactorWindow.write("R" .. reactorId .. ":")
    
    local statusColor = reactor.active and config.colors.active or config.colors.inactive
    reactorWindow.setTextColor(statusColor)
    reactorWindow.write(reactor.active and "ON" or "OFF")
    
    -- Temperature and burn rate (row 2)
    reactorWindow.setCursorPos(1, 2)
    reactorWindow.setTextColor(config.colors.text)
    local temp = reactor.temperature or 0
    if temp > 1000 then
        reactorWindow.setTextColor(config.colors.warning)
    end
    reactorWindow.write(string.format("%.0fK", temp))
    
    -- Fuel and waste (row 3)
    reactorWindow.setCursorPos(1, 3)
    local fuelColor = reactor.fuel_percent < 20 and config.colors.warning or config.colors.text
    reactorWindow.setTextColor(fuelColor)
    reactorWindow.write(string.format("F%.0f%%", reactor.fuel_percent or 0))
    
    -- Return button areas for click detection (adjusted for actual monitor position)
    return {
        reactorId = reactorId,
        toggleButton = {x = 1, y = 2, width = 4, height = 1},
        active = reactor.active,
        burnRate = reactor.burn_rate
    }
end

function ui.drawBatteryStatus(x, y, battery)
    batteryWindow.setBackgroundColor(config.colors.background)
    batteryWindow.clear()
    
    if not battery then
        batteryWindow.setCursorPos(1, 1)
        batteryWindow.setTextColor(config.colors.inactive)
        batteryWindow.write("No Batt")
        return
    end
    
    local percentColor = config.colors.text
    if battery.percent_full < 10 then
        percentColor = config.colors.critical
    elseif battery.percent_full < 30 then
        percentColor = config.colors.warning
    elseif battery.percent_full > 90 then
        percentColor = config.colors.warning
    end
    
    batteryWindow.setCursorPos(1, 1)
    batteryWindow.setTextColor(config.colors.header)
    batteryWindow.write("B:")
    batteryWindow.setTextColor(percentColor)
    batteryWindow.write(string.format("%.0f%%", battery.percent_full))
end

function ui.drawAlerts(x, y, alerts)
    alertWindow.setBackgroundColor(config.colors.background)
    alertWindow.clear()
    
    if not alerts or #alerts == 0 then
        alertWindow.setCursorPos(1, 1)
        alertWindow.setTextColor(config.colors.good)
        alertWindow.write("OK")
        return
    end
    
    -- Show last 2 alerts (2 rows available)
    local startIdx = math.max(1, #alerts - 1)
    local row = 1
    
    for i = startIdx, #alerts do
        local alert = alerts[i]
        if alert and row <= 2 then
            local alertColor = config.colors.warning
            
            if alert.level == "critical" or alert.level == "emergency" then
                alertColor = config.colors.critical
            elseif alert.level == "info" then
                alertColor = config.colors.text
            end
            
            alertWindow.setCursorPos(1, row)
            alertWindow.setTextColor(alertColor)
            
            -- Truncate message to fit in 4 characters
            local msg = string.sub(alert.message or "Alert", 1, 4)
            alertWindow.write(msg)
            
            row = row + 1
        end
    end
end

-- Simplified compact display for multiple reactors
function ui.drawCompactDisplay(systemStatus, alerts)
    ui.clear()
    
    -- Header
    ui.drawHeader("REACTOR")
    
    -- Draw first reactor (or show "No Data" if none)
    if systemStatus and systemStatus.reactors then
        local reactorId, reactor = next(systemStatus.reactors)
        if reactorId and reactor then
            ui.drawReactorStatus(1, 2, reactorId, reactor)
        else
            reactorWindow.setCursorPos(1, 1)
            reactorWindow.setTextColor(config.colors.inactive)
            reactorWindow.write("No React")
        end
    else
        reactorWindow.setCursorPos(1, 1)
        reactorWindow.setTextColor(config.colors.inactive)
        reactorWindow.write("Waiting..")
    end
    
    -- Draw battery status
    if systemStatus and systemStatus.battery then
        ui.drawBatteryStatus(5, 2, systemStatus.battery)
    end
    
    -- Draw alerts
    ui.drawAlerts(5, 3, alerts)
end

-- Control panel for 8x4 is too small, so we'll use a different approach
function ui.drawControlPanel(x, y)
    -- Return empty - controls will be handled by touch on reactor status
    return {}
end

function ui.formatTime(epoch)
    return os.date("%H:%M:%S", epoch / 1000)
end

function ui.getMonitor()
    return monitor
end

function ui.getSize()
    return width, height
end

function ui.isButtonClicked(button, clickX, clickY)
    return clickX >= button.x and clickX < button.x + button.width and
           clickY >= button.y and clickY < button.y + button.height
end

-- Disable graph drawing for 8x4 monitor
function ui.drawGraph(x, y, w, h, data, title, unit)
    -- Too small for graphs
end

return ui