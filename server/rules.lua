local rules = {}

local reactorStates = {}
local batteryState = nil
local lastDecisions = {}
local activeAlerts = {}  -- Track active alerts with timestamps

function rules.updateReactorState(reactorId, state)
    reactorStates[reactorId] = state
    reactorStates[reactorId].lastUpdate = os.epoch("utc")
end

function rules.updateBatteryState(state)
    batteryState = state
    batteryState.lastUpdate = os.epoch("utc")
end

function rules.checkSafetyConditions(reactorId, config)
    local reactor = reactorStates[reactorId]
    if not reactor then
        return false, "No reactor data"
    end
    
    -- Check battery timeout first (most critical)
    if batteryState then
        local timeSinceUpdate = (os.epoch("utc") - batteryState.lastUpdate) / 1000
        if timeSinceUpdate > 30 then
            return false, string.format("Battery offline for %d seconds - EMERGENCY SHUTDOWN", math.floor(timeSinceUpdate))
        end
    else
        return false, "No battery data available - EMERGENCY SHUTDOWN"
    end
    
    local checks = {
        {
            condition = reactor.temperature < config.safety_rules.max_temperature,
            reason = string.format("Temperature too high: %.1fK (max: %dK)", 
                reactor.temperature, config.safety_rules.max_temperature)
        },
        {
            condition = reactor.damage <= config.safety_rules.max_damage_percent,
            reason = string.format("Reactor damaged: %.1f%% (max: %d%%)", 
                reactor.damage, config.safety_rules.max_damage_percent)
        },
        {
            condition = reactor.coolant_percent > config.safety_rules.min_coolant_percent,
            reason = string.format("Insufficient coolant: %.1f%% (min: %d%%)", 
                reactor.coolant_percent, config.safety_rules.min_coolant_percent)
        },
        {
            condition = reactor.waste_percent < config.safety_rules.max_waste_percent,
            reason = string.format("Too much waste: %.1f%% (max: %d%%)", 
                reactor.waste_percent, config.safety_rules.max_waste_percent)
        },
        {
            condition = reactor.fuel_percent > config.safety_rules.min_fuel_percent,
            reason = string.format("Low fuel: %.1f%% (min: %d%%)", 
                reactor.fuel_percent, config.safety_rules.min_fuel_percent)
        },
        {
            condition = batteryState.percent_full < config.safety_rules.max_battery_percent,
            reason = string.format("Battery too full: %.1f%% (max: %d%%)", 
                batteryState.percent_full, config.safety_rules.max_battery_percent)
        }
    }
    
    for _, check in ipairs(checks) do
        if not check.condition then
            return false, check.reason
        end
    end
    
    return true, "All safety conditions met"
end

function rules.getReactorDecision(reactorId, config)
    local safe, reason = rules.checkSafetyConditions(reactorId, config)
    local reactor = reactorStates[reactorId]
    
    if not reactor then
        return {
            action = "none",
            reason = "No reactor data"
        }
    end
    
    local decision = {
        reactorId = reactorId,
        timestamp = os.epoch("utc"),
        safe = safe,
        safetyReason = reason
    }
    
    if not safe then
        if reactor.active then
            decision.action = "scram"
            decision.reason = "Safety violation: " .. reason
        else
            decision.action = "none"
            decision.reason = "Reactor offline - " .. reason
        end
    else
        decision.action = "none"
        decision.reason = "Reactor operating normally"
    end
    
    lastDecisions[reactorId] = decision
    return decision
end


function rules.getSystemStatus()
    local status = {
        reactors = {},
        battery = batteryState,
        timestamp = os.epoch("utc")
    }
    
    for id, reactor in pairs(reactorStates) do
        status.reactors[id] = {
            active = reactor.active,
            temperature = reactor.temperature,
            burn_rate = reactor.burn_rate,
            fuel_percent = reactor.fuel_percent,
            waste_percent = reactor.waste_percent,
            coolant_percent = reactor.coolant_percent,
            last_update = reactor.lastUpdate,
            last_decision = lastDecisions[id]
        }
    end
    
    return status
end

function rules.checkAlerts(config)
    local currentAlerts = {}
    local now = os.epoch("utc")
    
    -- Helper function to create alert key
    local function getAlertKey(source, alertType)
        return source .. ":" .. alertType
    end
    
    -- Check reactor alerts
    for reactorId, reactor in pairs(reactorStates) do
        local source = "reactor_" .. reactorId
        
        -- Temperature alerts
        if reactor.temperature > config.alerts.temperature_critical then
            local key = getAlertKey(source, "temp_critical")
            currentAlerts[key] = {
                level = "critical",
                source = source,
                message = "Critical temperature: " .. math.floor(reactor.temperature) .. "K",
                key = key
            }
        elseif reactor.temperature > config.alerts.temperature_warning then
            local key = getAlertKey(source, "temp_warning")
            currentAlerts[key] = {
                level = "warning",
                source = source,
                message = "High temperature: " .. math.floor(reactor.temperature) .. "K",
                key = key
            }
        end
        
        -- Waste alert
        if reactor.waste_percent > config.alerts.waste_warning then
            local key = getAlertKey(source, "waste")
            currentAlerts[key] = {
                level = "warning",
                source = source,
                message = "High waste level: " .. string.format("%.1f%%", reactor.waste_percent),
                key = key
            }
        end
        
        -- Fuel alert
        if reactor.fuel_percent < config.alerts.fuel_warning then
            local key = getAlertKey(source, "fuel")
            currentAlerts[key] = {
                level = "warning",
                source = source,
                message = "Low fuel: " .. string.format("%.1f%%", reactor.fuel_percent),
                key = key
            }
        end
        
        -- Coolant alert
        if reactor.coolant_percent < config.alerts.coolant_warning then
            local key = getAlertKey(source, "coolant")
            currentAlerts[key] = {
                level = "warning",
                source = source,
                message = "Low coolant: " .. string.format("%.1f%%", reactor.coolant_percent),
                key = key
            }
        end
    end
    
    -- Check battery alerts
    if batteryState then
        local timeSinceUpdate = (now - batteryState.lastUpdate) / 1000
        if timeSinceUpdate > 30 then
            local key = getAlertKey("battery", "offline_critical")
            currentAlerts[key] = {
                level = "critical",
                source = "battery",
                message = string.format("BATTERY OFFLINE %ds - REACTORS SCRAMMED", math.floor(timeSinceUpdate)),
                key = key
            }
        elseif timeSinceUpdate > 20 then
            local key = getAlertKey("battery", "offline_warning")
            currentAlerts[key] = {
                level = "warning",
                source = "battery",
                message = string.format("Battery not responding for %d seconds", math.floor(timeSinceUpdate)),
                key = key
            }
        end
        
        -- Battery level alert
        if batteryState.percent_full > config.alerts.battery_warning then
            local key = getAlertKey("battery", "level")
            currentAlerts[key] = {
                level = "warning",
                source = "battery",
                message = "Battery nearly full: " .. string.format("%.1f%%", batteryState.percent_full),
                key = key
            }
        end
    else
        local key = getAlertKey("battery", "no_data")
        currentAlerts[key] = {
            level = "critical",
            source = "battery",
            message = "NO BATTERY DATA - REACTORS SCRAMMED",
            key = key
        }
    end
    
    -- Update active alerts tracker
    for key, alert in pairs(currentAlerts) do
        if not activeAlerts[key] then
            -- New alert
            activeAlerts[key] = {
                alert = alert,
                firstSeen = now,
                lastSeen = now
            }
        else
            -- Existing alert - update last seen time
            activeAlerts[key].lastSeen = now
            activeAlerts[key].alert = alert  -- Update message in case values changed
        end
    end
    
    -- Clear old alerts that haven't been seen for 30 seconds
    local alertsToRemove = {}
    for key, alertData in pairs(activeAlerts) do
        if not currentAlerts[key] then
            -- Alert condition no longer present
            local timeSinceCleared = (now - alertData.lastSeen) / 1000
            if timeSinceCleared > 30 then
                table.insert(alertsToRemove, key)
            end
        end
    end
    
    -- Remove cleared alerts and track them
    rules._clearedAlerts = {}
    for _, key in ipairs(alertsToRemove) do
        if activeAlerts[key] then
            table.insert(rules._clearedAlerts, activeAlerts[key].alert)
        end
        activeAlerts[key] = nil
    end
    
    -- Return only active alerts
    local alerts = {}
    for _, alertData in pairs(activeAlerts) do
        table.insert(alerts, alertData.alert)
    end
    
    return alerts
end

function rules.getClearedAlerts()
    local cleared = rules._clearedAlerts or {}
    rules._clearedAlerts = {}  -- Reset after reading
    return cleared
end

function rules.isStale(lastUpdate, timeout)
    return (os.epoch("utc") - lastUpdate) > (timeout * 1000)
end

function rules.checkComponentHealth(config)
    local health = {
        reactors = {},
        battery = true
    }
    
    for reactorId, reactor in pairs(reactorStates) do
        health.reactors[reactorId] = not rules.isStale(reactor.lastUpdate, config.heartbeat_timeout)
    end
    
    if batteryState then
        health.battery = not rules.isStale(batteryState.lastUpdate, config.heartbeat_timeout)
    else
        health.battery = false
    end
    
    return health
end

return rules