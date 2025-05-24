local network = {}

local modem = nil
local channels = {}
local messageHandlers = {}
local responseHandlers = {}
local messageId = 0
function network.init(modemSide, listenChannels)
    modem = peripheral.find("modem") or peripheral.wrap(modemSide)
    if not modem then
        error("No modem found on side: " .. tostring(modemSide))
    end
    
    if not modem.isWireless() then
        error("Modem must be wireless")
    end
    
    channels = listenChannels or {}
    
    for _, channel in ipairs(channels) do
        modem.open(channel)
        print("Opened channel: " .. channel)
    end
    
    return true
end

function network.generateMessageId()
    messageId = messageId + 1
    return os.getComputerID() .. "_" .. messageId .. "_" .. os.epoch("utc")
end

function network.createMessage(msgType, command, data, target)
    return {
        id = network.generateMessageId(),
        type = msgType,
        sender = os.getComputerID(),
        target = target or "all",
        command = command,
        data = data or {},
        timestamp = os.epoch("utc")
    }
end

function network.send(channel, message)
    if not modem then
        error("Network not initialized")
    end
    
    modem.transmit(channel, channel, message)
end

function network.broadcast(message, channel)
    if not modem then
        error("Network not initialized")
    end
    
    local broadcastChannel = channel or channels[1]
    modem.transmit(broadcastChannel, broadcastChannel, message)
end

function network.request(channel, command, data, timeout)
    local message = network.createMessage("request", command, data)
    local responseReceived = false
    local response = nil
    
    responseHandlers[message.id] = function(msg)
        responseReceived = true
        response = msg
    end
    
    network.send(channel, message)
    
    local timer = os.startTimer(timeout or 5)
    
    while not responseReceived do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "timer" and p1 == timer then
            responseHandlers[message.id] = nil
            return false, "Timeout"
        elseif event == "modem_message" then
            network.handleModemMessage(p1, p2, p3, p4, p5)
        end
    end
    
    responseHandlers[message.id] = nil
    return true, response
end

function network.respond(originalMessage, data, status)
    local response = network.createMessage("response", originalMessage.command, data, originalMessage.sender)
    response.requestId = originalMessage.id
    response.status = status or "ok"
    
    for _, channel in ipairs(channels) do
        network.send(channel, response)
    end
end

function network.handleModemMessage(side, senderChannel, replyChannel, message, distance)
    if type(message) ~= "table" then
        return
    end
    
    if message.target ~= "all" and message.target ~= os.getComputerID() then
        return
    end
    
    if message.type == "response" and message.requestId and responseHandlers[message.requestId] then
        responseHandlers[message.requestId](message)
        return
    end
    
    for command, handler in pairs(messageHandlers) do
        if message.command == command then
            local success, err = pcall(handler, message, senderChannel)
            if not success then
                print("Error handling " .. command .. ": " .. tostring(err))
            end
        end
    end
end

function network.on(command, handler)
    messageHandlers[command] = handler
end

function network.removeHandler(command)
    messageHandlers[command] = nil
end

function network.listen()
    while true do
        local event, side, senderChannel, replyChannel, message, distance = os.pullEvent("modem_message")
        network.handleModemMessage(side, senderChannel, replyChannel, message, distance)
    end
end

function network.listenWithTimeout(timeout)
    local timer = os.startTimer(timeout)
    
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "timer" and p1 == timer then
            return false
        elseif event == "modem_message" then
            network.handleModemMessage(p1, p2, p3, p4, p5)
            return true
        end
    end
end

function network.getModem()
    return modem
end

function network.getChannels()
    return channels
end

return network