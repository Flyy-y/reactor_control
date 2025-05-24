local ui = {}

local monitor = nil
local width, height = 0, 0
local config = nil

-- Helper function to format RF values
local function formatRF(value)
    local absValue = math.abs(value)
    local sign = value < 0 and "-" or value > 0 and "+" or ""
    
    if absValue >= 1e9 then
        return string.format("%s%.1fG", sign, absValue / 1e9)
    elseif absValue >= 1e6 then
        return string.format("%s%.1fM", sign, absValue / 1e6)
    elseif absValue >= 1e3 then
        return string.format("%s%.1fK", sign, absValue / 1e3)
    else
        return string.format("%s%.0f", sign, absValue)
    end
end

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
    print("Monitor size: " .. width .. "x" .. height)
    
    return true
end

function ui.clear()
    monitor.setBackgroundColor(config.colors.background)
    monitor.clear()
end

function ui.drawHeader(title)
    monitor.setCursorPos(1, 1)
    monitor.setBackgroundColor(config.colors.header)
    monitor.setTextColor(config.colors.background)
    monitor.clearLine()
    
    local padding = math.floor((width - #title) / 2)
    monitor.setCursorPos(padding, 1)
    monitor.write(title)
    
    monitor.setBackgroundColor(config.colors.background)
    monitor.setTextColor(config.colors.text)
end

function ui.drawBox(x, y, w, h, title)
    monitor.setTextColor(config.colors.border)
    
    monitor.setCursorPos(x, y)
    monitor.write("+" .. string.rep("-", w - 2) .. "+")
    
    for i = 1, h - 2 do
        monitor.setCursorPos(x, y + i)
        monitor.write("|")
        monitor.setCursorPos(x + w - 1, y + i)
        monitor.write("|")
    end
    
    monitor.setCursorPos(x, y + h - 1)
    monitor.write("+" .. string.rep("-", w - 2) .. "+")
    
    if title then
        monitor.setCursorPos(x + 2, y)
        monitor.setTextColor(config.colors.header)
        monitor.write(" " .. title .. " ")
    end
    
    monitor.setTextColor(config.colors.text)
end

function ui.drawReactorStatus(x, y, reactorId, reactor)
    -- Calculate dynamic box size based on available space
    local boxWidth = math.floor(width / 2) - 2
    local boxHeight = math.floor((height - 3) / 2)
    
    ui.drawBox(x, y, boxWidth, boxHeight, "Reactor " .. reactorId)
    
    -- Add status indicator for reactor data freshness
    local statusIndicator = "●"
    local dataStatusColor = config.colors.inactive
    local currentTime = os.epoch("utc")
    
    if reactor and reactor.last_update then
        local timeSinceUpdate = (currentTime - reactor.last_update) / 1000  -- Convert to seconds
        if timeSinceUpdate <= 10 then
            dataStatusColor = config.colors.good  -- Green for fresh data
        else
            dataStatusColor = config.colors.critical  -- Red for stale data
        end
    end
    
    -- Draw status indicator in top right of reactor box
    monitor.setCursorPos(x + boxWidth - 2, y + 1)
    monitor.setTextColor(dataStatusColor)
    monitor.write(statusIndicator)
    monitor.setTextColor(config.colors.text)
    
    local statusColor = reactor.active and config.colors.active or config.colors.inactive
    local statusText = reactor.active and "ONLINE" or "OFFLINE"
    
    monitor.setCursorPos(x + 2, y + 2)
    monitor.setTextColor(statusColor)
    monitor.write("Status: " .. statusText)
    
    monitor.setTextColor(config.colors.text)
    monitor.setCursorPos(x + 2, y + 3)
    local tempColor = reactor.temperature > 1000 and config.colors.warning or config.colors.text
    monitor.setTextColor(tempColor)
    monitor.write(string.format("Temp:    %4.0fK", reactor.temperature or 0))
    
    monitor.setTextColor(config.colors.text)
    monitor.setCursorPos(x + 2, y + 4)
    monitor.write(string.format("Burn:    %4.1f mB/t", reactor.burn_rate or 0))
    
    -- Add burn rate control buttons if reactor is active
    if reactor.active then
        -- Decrease button
        monitor.setCursorPos(x + boxWidth - 8, y + 4)
        monitor.setBackgroundColor(config.colors.warning)
        monitor.setTextColor(config.colors.background)
        monitor.write(" - ")
        
        -- Increase button  
        monitor.setCursorPos(x + boxWidth - 4, y + 4)
        monitor.setBackgroundColor(config.colors.good)
        monitor.setTextColor(config.colors.background)
        monitor.write(" + ")
        
        monitor.setBackgroundColor(config.colors.background)
        monitor.setTextColor(config.colors.text)
    end
    
    if y + 5 < y + boxHeight - 1 then
        monitor.setCursorPos(x + 2, y + 5)
        local fuelColor = reactor.fuel_percent < 20 and config.colors.warning or config.colors.text
        monitor.setTextColor(fuelColor)
        monitor.write(string.format("Fuel:    %4.1f%%", reactor.fuel_percent or 0))
    end
    
    if y + 6 < y + boxHeight - 1 then
        monitor.setCursorPos(x + 2, y + 6)
        local wasteColor = reactor.waste_percent > 3 and config.colors.warning or config.colors.text
        monitor.setTextColor(wasteColor)
        monitor.write(string.format("Waste:   %4.1f%%", reactor.waste_percent or 0))
    end
    
    if y + 7 < y + boxHeight - 1 then
        monitor.setCursorPos(x + 2, y + 7)
        local coolantColor = reactor.coolant_percent < 97 and config.colors.warning or config.colors.text
        monitor.setTextColor(coolantColor)
        monitor.write(string.format("Coolant: %4.1f%%", reactor.coolant_percent or 0))
    end
    
    -- Control button at bottom of box
    local buttonY = y + boxHeight - 2
    monitor.setCursorPos(x + 2, buttonY)
    if reactor.active then
        monitor.setBackgroundColor(config.colors.inactive)
        monitor.setTextColor(config.colors.text)
        monitor.write(" SCRAM ")
    else
        monitor.setBackgroundColor(config.colors.active)
        monitor.setTextColor(config.colors.background)
        monitor.write(" START ")
    end
    monitor.setBackgroundColor(config.colors.background)
    
    monitor.setTextColor(config.colors.text)
    
    local buttons = {
        reactorId = reactorId,
        toggleButton = {x = x + 2, y = buttonY, width = 7, height = 1},
        active = reactor.active,
        burnRate = reactor.burn_rate
    }
    
    -- Add burn rate control buttons if reactor is active
    if reactor.active then
        buttons.decreaseBurnButton = {x = x + boxWidth - 8, y = y + 4, width = 3, height = 1}
        buttons.increaseBurnButton = {x = x + boxWidth - 4, y = y + 4, width = 3, height = 1}
    end
    
    return buttons
end

function ui.drawBatteryStatus(x, y, battery)
    local boxWidth = math.floor(width / 2) - 2
    local boxHeight = math.floor((height - 3) / 2)
    
    ui.drawBox(x, y, boxWidth, boxHeight, "Battery")
    
    -- Add status indicator for battery data freshness
    local statusIndicator = "●"
    local statusColor = config.colors.inactive
    local currentTime = os.epoch("utc")
    
    if battery and battery.lastUpdate then
        local timeSinceUpdate = (currentTime - battery.lastUpdate) / 1000  -- Convert to seconds
        if timeSinceUpdate <= 10 then
            statusColor = config.colors.good  -- Green for fresh data
        else
            statusColor = config.colors.critical  -- Red for stale data
        end
    end
    
    -- Draw status indicator in top right of battery box
    monitor.setCursorPos(x + boxWidth - 2, y + 1)
    monitor.setTextColor(statusColor)
    monitor.write(statusIndicator)
    monitor.setTextColor(config.colors.text)
    
    if not battery then
        monitor.setCursorPos(x + 2, y + 2)
        monitor.setTextColor(config.colors.inactive)
        monitor.write("No data")
        monitor.setTextColor(config.colors.text)
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
    
    monitor.setCursorPos(x + 2, y + 2)
    monitor.setTextColor(percentColor)
    monitor.write(string.format("Level: %.1f%%", battery.percent_full))
    
    monitor.setTextColor(config.colors.text)
    monitor.setCursorPos(x + 2, y + 3)
    local netFlow = battery.input_rate - battery.output_rate
    local flowColor = netFlow > 0 and config.colors.good or config.colors.warning
    monitor.setTextColor(flowColor)
    monitor.write(string.format("Net: %s RF/t", formatRF(netFlow)))
    
    if y + 4 < y + boxHeight - 1 then
        monitor.setTextColor(config.colors.text)
        monitor.setCursorPos(x + 2, y + 4)
        monitor.write(string.format("In:  %s RF/t", formatRF(battery.input_rate)))
    end
    
    if y + 5 < y + boxHeight - 1 then
        monitor.setCursorPos(x + 2, y + 5)
        monitor.write(string.format("Out: %s RF/t", formatRF(battery.output_rate)))
    end
end

function ui.drawAlerts(x, y, alerts)
    local boxWidth = width - x + 1
    local boxHeight = height - y + 1
    
    ui.drawBox(x, y, boxWidth, boxHeight, "Alerts")
    
    if not alerts or #alerts == 0 then
        monitor.setCursorPos(x + 2, y + 2)
        monitor.setTextColor(config.colors.good)
        monitor.write("No active alerts")
        monitor.setTextColor(config.colors.text)
        return
    end
    
    local maxAlerts = boxHeight - 3
    local displayCount = math.min(#alerts, maxAlerts)
    
    for i = 1, displayCount do
        local alert = alerts[#alerts - i + 1]
        local alertColor = config.colors.warning
        
        if alert.level == "critical" or alert.level == "emergency" then
            alertColor = config.colors.critical
        elseif alert.level == "info" then
            alertColor = config.colors.text
        end
        
        monitor.setCursorPos(x + 2, y + 1 + i)
        monitor.setTextColor(alertColor)
        
        local message = string.sub(alert.message, 1, boxWidth - 4)
        monitor.write(message)
    end
    
    monitor.setTextColor(config.colors.text)
end

function ui.drawControlPanel(x, y)
    local boxWidth = math.min(30, width - x + 1)
    local boxHeight = 6
    
    if y + boxHeight > height then
        return {}
    end
    
    ui.drawBox(x, y, boxWidth, boxHeight, "System Control")
    
    monitor.setCursorPos(x + 2, y + 2)
    monitor.write("Emergency:")
    
    monitor.setCursorPos(x + 2, y + 3)
    monitor.setBackgroundColor(config.colors.critical)
    monitor.setTextColor(config.colors.text)
    monitor.write(" SCRAM ALL ")
    monitor.setBackgroundColor(config.colors.background)
    
    monitor.setCursorPos(x + 15, y + 3)
    monitor.setBackgroundColor(config.colors.active)
    monitor.setTextColor(config.colors.background)
    monitor.write(" START ALL ")
    monitor.setBackgroundColor(config.colors.background)
    monitor.setTextColor(config.colors.text)
    
    return {
        scramAllButton = {x = x + 2, y = y + 3, width = 11, height = 1},
        startAllButton = {x = x + 15, y = y + 3, width = 11, height = 1}
    }
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
    if not button or not button.x or not button.y or not button.width or not button.height then
        return false
    end
    return clickX >= button.x and clickX < button.x + button.width and
           clickY >= button.y and clickY < button.y + button.height
end

function ui.drawGraph(x, y, w, h, data, title, unit)
    if #data < 2 or h < 5 or w < 10 then
        return
    end
    
    ui.drawBox(x, y, w, h, title)
    
    local graphWidth = w - 4
    local graphHeight = h - 4
    local dataPoints = math.min(#data, graphWidth)
    
    local maxVal = 0
    local minVal = math.huge
    for i = #data - dataPoints + 1, #data do
        if data[i] then
            maxVal = math.max(maxVal, data[i])
            minVal = math.min(minVal, data[i])
        end
    end
    
    if maxVal == minVal then
        maxVal = minVal + 1
    end
    
    for i = 0, dataPoints - 1 do
        local dataIdx = #data - dataPoints + i + 1
        if data[dataIdx] then
            local val = data[dataIdx]
            local height = math.floor((val - minVal) / (maxVal - minVal) * graphHeight)
            
            for j = 0, height do
                monitor.setCursorPos(x + 2 + i, y + h - 3 - j)
                monitor.write("#")
            end
        end
    end
    
    monitor.setCursorPos(x + 2, y + 1)
    monitor.write(string.format("%.1f%s", maxVal, unit or ""))
    
    monitor.setCursorPos(x + 2, y + h - 2)
    monitor.write(string.format("%.1f%s", minVal, unit or ""))
end

return ui