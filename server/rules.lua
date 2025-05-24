local rules = {}

local reactorStates = {}
local batteryState = nil
local lastDecisions = {}

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
        }
    }
    
    if batteryState then
        table.insert(checks, {
            condition = batteryState.percent_full < config.safety_rules.max_battery_percent,
            reason = string.format("Battery too full: %.1f%% (max: %d%%)", 
                batteryState.percent_full, config.safety_rules.max_battery_percent)
        })
    else
        table.insert(checks, {
            condition = false,
            reason = "No battery data available"
        })
    end
    
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
    local alerts = {}
    
    for reactorId, reactor in pairs(reactorStates) do
        if reactor.temperature > config.alerts.temperature_critical then
            table.insert(alerts, {
                level = "critical",
                source = "reactor_" .. reactorId,
                message = "Critical temperature: " .. math.floor(reactor.temperature) .. "K"
            })
        elseif reactor.temperature > config.alerts.temperature_warning then
            table.insert(alerts, {
                level = "warning",
                source = "reactor_" .. reactorId,
                message = "High temperature: " .. math.floor(reactor.temperature) .. "K"
            })
        end
        
        if reactor.waste_percent > config.alerts.waste_warning then
            table.insert(alerts, {
                level = "warning",
                source = "reactor_" .. reactorId,
                message = "High waste level: " .. string.format("%.1f%%", reactor.waste_percent)
            })
        end
        
        if reactor.fuel_percent < config.alerts.fuel_warning then
            table.insert(alerts, {
                level = "warning",
                source = "reactor_" .. reactorId,
                message = "Low fuel: " .. string.format("%.1f%%", reactor.fuel_percent)
            })
        end
        
        if reactor.coolant_percent < config.alerts.coolant_warning then
            table.insert(alerts, {
                level = "warning",
                source = "reactor_" .. reactorId,
                message = "Low coolant: " .. string.format("%.1f%%", reactor.coolant_percent)
            })
        end
    end
    
    if batteryState and batteryState.percent_full > config.alerts.battery_warning then
        table.insert(alerts, {
            level = "warning",
            source = "battery",
            message = "Battery nearly full: " .. string.format("%.1f%%", batteryState.percent_full)
        })
    end
    
    return alerts
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