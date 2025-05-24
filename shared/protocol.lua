local protocol = {}

protocol.commands = {
    REACTOR_STATUS = "reactor_status",
    BATTERY_STATUS = "battery_status",
    REACTOR_CONTROL = "reactor_control",
    DISPLAY_REQUEST = "display_request",
    SYSTEM_STATUS = "system_status",
    ALERT = "alert",
    HEARTBEAT = "heartbeat",
    CONFIG_UPDATE = "config_update",
    DISCOVER_REACTORS = "discover_reactors",
    REACTOR_INFO = "reactor_info"
}

protocol.messageTypes = {
    REQUEST = "request",
    RESPONSE = "response",
    BROADCAST = "broadcast"
}

protocol.reactorActions = {
    ACTIVATE = "activate",
    SCRAM = "scram",
    SET_BURN_RATE = "set_burn_rate"
}

protocol.alertLevels = {
    INFO = "info",
    WARNING = "warning",
    CRITICAL = "critical",
    EMERGENCY = "emergency"
}

protocol.channels = {
    SERVER = 100,
    REACTOR_BASE = 101,
    BATTERY = 110,
    DISPLAY_BASE = 120
}

function protocol.createReactorStatus(reactorId, stats)
    return {
        reactor_id = reactorId,
        active = stats.active,
        temperature = stats.temperature,
        burn_rate = stats.burnRate,
        actual_burn_rate = stats.actualBurnRate,
        max_burn_rate = stats.maxBurnRate,
        damage = stats.damage,
        fuel = stats.fuel,
        fuel_capacity = stats.fuelCapacity,
        fuel_percent = stats.fuelPercent,
        waste = stats.waste,
        waste_capacity = stats.wasteCapacity,
        waste_percent = stats.wastePercent,
        coolant = stats.coolant,
        coolant_capacity = stats.coolantCapacity,
        coolant_percent = stats.coolantPercent,
        heated_coolant = stats.heatedCoolant,
        heated_coolant_capacity = stats.heatedCoolantCapacity,
        heated_coolant_percent = stats.heatedCoolantPercent,
        boil_efficiency = stats.boilEfficiency,
        heating_rate = stats.heatingRate,
        environmental_loss = stats.environmentalLoss
    }
end

function protocol.createBatteryStatus(stats)
    return {
        energy_stored = stats.energy,
        energy_capacity = stats.maxEnergy,
        percent_full = (stats.energy / stats.maxEnergy) * 100,
        input_rate = stats.lastInput,
        output_rate = stats.lastOutput,
        transfer_cap = stats.transferCap
    }
end

function protocol.createReactorControl(reactorId, action, value)
    return {
        reactor_id = reactorId,
        action = action,
        value = value
    }
end

function protocol.createAlert(level, source, message, data)
    return {
        level = level,
        source = source,
        message = message,
        data = data or {},
        timestamp = os.epoch("utc")
    }
end

function protocol.createHeartbeat(componentType, componentId, status)
    return {
        component_type = componentType,
        component_id = componentId,
        status = status or "online",
        uptime = os.clock(),
        timestamp = os.epoch("utc")
    }
end

function protocol.validateMessage(message)
    if type(message) ~= "table" then
        return false, "Message must be a table"
    end
    
    if not message.type or not message.command or not message.sender then
        return false, "Missing required fields"
    end
    
    if not message.timestamp then
        return false, "Missing timestamp"
    end
    
    local age = os.epoch("utc") - message.timestamp
    if age > 60000 then
        return false, "Message too old"
    end
    
    return true
end

function protocol.getReactorChannel(reactorId)
    return protocol.channels.REACTOR_BASE + (reactorId - 1)
end

function protocol.getDisplayChannel(displayId)
    return protocol.channels.DISPLAY_BASE + (displayId - 1)
end

return protocol