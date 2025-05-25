local storage = {}

local config = nil

function storage.init(serverConfig)
    config = serverConfig
end

-- Data history functions removed - no longer storing historical data

-- History retrieval functions removed

-- Save/load functions removed

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

-- Stats function removed

return storage