local storage = {}

local dataHistory = {
    reactors = {},
    battery = {},
    alerts = {},
    decisions = {}
}

local config = nil

function storage.init(serverConfig)
    config = serverConfig
    storage.load()
end

function storage.addReactorData(reactorId, data)
    if not dataHistory.reactors[reactorId] then
        dataHistory.reactors[reactorId] = {}
    end
    
    table.insert(dataHistory.reactors[reactorId], {
        timestamp = os.epoch("utc"),
        data = data
    })
    
    while #dataHistory.reactors[reactorId] > config.data_retention.history_size do
        table.remove(dataHistory.reactors[reactorId], 1)
    end
end

function storage.addBatteryData(data)
    table.insert(dataHistory.battery, {
        timestamp = os.epoch("utc"),
        data = data
    })
    
    while #dataHistory.battery > config.data_retention.history_size do
        table.remove(dataHistory.battery, 1)
    end
end

function storage.addAlert(alert)
    table.insert(dataHistory.alerts, alert)
    
    while #dataHistory.alerts > config.data_retention.history_size do
        table.remove(dataHistory.alerts, 1)
    end
end

function storage.addDecision(decision)
    table.insert(dataHistory.decisions, decision)
    
    while #dataHistory.decisions > config.data_retention.history_size do
        table.remove(dataHistory.decisions, 1)
    end
end

function storage.getReactorHistory(reactorId, count)
    if not dataHistory.reactors[reactorId] then
        return {}
    end
    
    local history = dataHistory.reactors[reactorId]
    local startIdx = math.max(1, #history - (count or 100) + 1)
    
    local result = {}
    for i = startIdx, #history do
        table.insert(result, history[i])
    end
    
    return result
end

function storage.getBatteryHistory(count)
    local startIdx = math.max(1, #dataHistory.battery - (count or 100) + 1)
    
    local result = {}
    for i = startIdx, #dataHistory.battery do
        table.insert(result, dataHistory.battery[i])
    end
    
    return result
end

function storage.getRecentAlerts(count)
    local startIdx = math.max(1, #dataHistory.alerts - (count or 50) + 1)
    
    local result = {}
    for i = startIdx, #dataHistory.alerts do
        table.insert(result, dataHistory.alerts[i])
    end
    
    return result
end

function storage.getRecentDecisions(count)
    local startIdx = math.max(1, #dataHistory.decisions - (count or 50) + 1)
    
    local result = {}
    for i = startIdx, #dataHistory.decisions do
        table.insert(result, dataHistory.decisions[i])
    end
    
    return result
end

function storage.save()
    local file = fs.open("data_history.dat", "w")
    if file then
        file.write(textutils.serialize(dataHistory))
        file.close()
        return true
    end
    return false
end

function storage.load()
    if fs.exists("data_history.dat") then
        local file = fs.open("data_history.dat", "r")
        if file then
            local data = file.readAll()
            file.close()
            
            local loaded = textutils.unserialize(data)
            if loaded then
                dataHistory = loaded
                
                if not dataHistory.reactors then dataHistory.reactors = {} end
                if not dataHistory.battery then dataHistory.battery = {} end
                if not dataHistory.alerts then dataHistory.alerts = {} end
                if not dataHistory.decisions then dataHistory.decisions = {} end
                
                return true
            end
        end
    end
    return false
end

function storage.log(message)
    if not config.logging.enabled then
        return
    end
    
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local logEntry = "[" .. timestamp .. "] " .. message
    
    print(logEntry)
    
    local file = fs.open(config.logging.file, "a")
    if file then
        file.writeLine(logEntry)
        file.close()
    end
end

function storage.getStats()
    local stats = {
        reactor_entries = 0,
        battery_entries = #dataHistory.battery,
        alert_count = #dataHistory.alerts,
        decision_count = #dataHistory.decisions
    }
    
    for reactorId, history in pairs(dataHistory.reactors) do
        stats.reactor_entries = stats.reactor_entries + #history
    end
    
    return stats
end

return storage