local reactor_api = {}

local reactor = nil
local side = nil

function reactor_api.findReactor()
    local peripherals = peripheral.getNames()
    
    for _, name in ipairs(peripherals) do
        local pType = peripheral.getType(name)
        if pType == "fissionReactor" or pType == "fissionReactorLogicAdapter" then
            reactor = peripheral.wrap(name)
            side = name
            print("Found fission reactor on: " .. name)
            return true
        end
    end
    
    return false
end

function reactor_api.initialize()
    if not reactor_api.findReactor() then
        error("No fission reactor found! Please connect a Mekanism Fission Reactor")
    end
    
    return true
end

function reactor_api.isActive()
    if not reactor then return false end
    return reactor.getStatus()
end

function reactor_api.activate()
    if not reactor then return false end
    if reactor_api.isActive() then return true end
    reactor.activate()
    return true
end

function reactor_api.scram()
    if not reactor then return false end
    reactor.scram()
    return true
end

function reactor_api.getBurnRate()
    if not reactor then return 0 end
    return reactor.getBurnRate()
end

function reactor_api.getActualBurnRate()
    if not reactor then return 0 end
    return reactor.getActualBurnRate()
end

function reactor_api.setBurnRate(rate)
    if not reactor then return false end
    reactor.setBurnRate(rate)
    return true
end

function reactor_api.getMaxBurnRate()
    if not reactor then return 0 end
    return reactor.getMaxBurnRate()
end

function reactor_api.getTemperature()
    if not reactor then return 0 end
    return reactor.getTemperature()
end

function reactor_api.getDamagePercent()
    if not reactor then return 0 end
    return reactor.getDamagePercent()
end

function reactor_api.getBoilEfficiency()
    if not reactor then return 0 end
    return reactor.getBoilEfficiency()
end

function reactor_api.getHeatCapacity()
    if not reactor then return 0 end
    return reactor.getHeatCapacity()
end

function reactor_api.getFuelCapacity()
    if not reactor then return 0 end
    return reactor.getFuelCapacity()
end

function reactor_api.getFuelAmount()
    if not reactor then return 0 end
    return reactor.getFuelAmount()
end

function reactor_api.getFuelPercent()
    if not reactor then return 0 end
    local capacity = reactor_api.getFuelCapacity()
    if capacity == 0 then return 0 end
    return (reactor_api.getFuelAmount() / capacity) * 100
end

function reactor_api.getWasteCapacity()
    if not reactor then return 0 end
    return reactor.getWasteCapacity()
end

function reactor_api.getWasteAmount()
    if not reactor then return 0 end
    return reactor.getWasteAmount()
end

function reactor_api.getWastePercent()
    if not reactor then return 0 end
    local capacity = reactor_api.getWasteCapacity()
    if capacity == 0 then return 0 end
    return (reactor_api.getWasteAmount() / capacity) * 100
end

function reactor_api.getCoolantCapacity()
    if not reactor then return 0 end
    return reactor.getCoolantCapacity()
end

function reactor_api.getCoolantAmount()
    if not reactor then return 0 end
    return reactor.getCoolantAmount()
end

function reactor_api.getCoolantPercent()
    if not reactor then return 0 end
    local capacity = reactor_api.getCoolantCapacity()
    if capacity == 0 then return 0 end
    return (reactor_api.getCoolantAmount() / capacity) * 100
end

function reactor_api.getHeatedCoolantCapacity()
    if not reactor then return 0 end
    return reactor.getHeatedCoolantCapacity()
end

function reactor_api.getHeatedCoolantAmount()
    if not reactor then return 0 end
    return reactor.getHeatedCoolantAmount()
end

function reactor_api.getHeatedCoolantPercent()
    if not reactor then return 0 end
    local capacity = reactor_api.getHeatedCoolantCapacity()
    if capacity == 0 then return 0 end
    return (reactor_api.getHeatedCoolantAmount() / capacity) * 100
end

function reactor_api.getStats()
    if not reactor then return nil end
    
    return {
        active = reactor_api.isActive(),
        temperature = reactor_api.getTemperature(),
        damage = reactor_api.getDamagePercent(),
        burnRate = reactor_api.getBurnRate(),
        actualBurnRate = reactor_api.getActualBurnRate(),
        maxBurnRate = reactor_api.getMaxBurnRate(),
        boilEfficiency = reactor_api.getBoilEfficiency(),
        heatCapacity = reactor_api.getHeatCapacity(),
        fuelAmount = reactor_api.getFuelAmount(),
        fuelCapacity = reactor_api.getFuelCapacity(),
        fuelPercent = reactor_api.getFuelPercent(),
        wasteAmount = reactor_api.getWasteAmount(),
        wasteCapacity = reactor_api.getWasteCapacity(),
        wastePercent = reactor_api.getWastePercent(),
        coolantAmount = reactor_api.getCoolantAmount(),
        coolantCapacity = reactor_api.getCoolantCapacity(),
        coolantPercent = reactor_api.getCoolantPercent(),
        heatedCoolantAmount = reactor_api.getHeatedCoolantAmount(),
        heatedCoolantCapacity = reactor_api.getHeatedCoolantCapacity(),
        heatedCoolantPercent = reactor_api.getHeatedCoolantPercent()
    }
end

return reactor_api