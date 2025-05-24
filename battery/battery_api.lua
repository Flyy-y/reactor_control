local battery_api = {}

local battery = nil
local side = nil

function battery_api.findBattery()
    local peripherals = peripheral.getNames()
    
    for _, name in ipairs(peripherals) do
        local pType = peripheral.getType(name)
        if pType == "inductionPort" or pType == "InductionMatrix" then
            battery = peripheral.wrap(name)
            side = name
            print("Found induction matrix on: " .. name)
            return true
        end
    end
    
    return false
end

function battery_api.initialize()
    if not battery_api.findBattery() then
        error("No induction matrix found! Please connect a Mekanism Induction Matrix")
    end
    
    return true
end

function battery_api.getEnergy()
    if not battery then return 0 end
    return battery.getEnergy()
end

function battery_api.getMaxEnergy()
    if not battery then return 0 end
    return battery.getMaxEnergy()
end

function battery_api.getLastInput()
    if not battery then return 0 end
    return battery.getLastInput()
end

function battery_api.getLastOutput()
    if not battery then return 0 end
    return battery.getLastOutput()
end

function battery_api.getTransferCap()
    if not battery then return 0 end
    return battery.getTransferCap()
end

function battery_api.getInstalledCells()
    if not battery then return 0 end
    return battery.getInstalledCells()
end

function battery_api.getInstalledProviders()
    if not battery then return 0 end
    return battery.getInstalledProviders()
end

function battery_api.getStats()
    if not battery then return nil end
    
    local energy = battery_api.getEnergy()
    local maxEnergy = battery_api.getMaxEnergy()
    
    return {
        energy = energy,
        maxEnergy = maxEnergy,
        energyPercent = (energy / maxEnergy) * 100,
        lastInput = battery_api.getLastInput(),
        lastOutput = battery_api.getLastOutput(),
        netFlow = battery_api.getLastInput() - battery_api.getLastOutput(),
        transferCap = battery_api.getTransferCap(),
        cells = battery_api.getInstalledCells(),
        providers = battery_api.getInstalledProviders()
    }
end

function battery_api.getFormattedEnergy(energy)
    if energy >= 1e12 then
        return string.format("%.2f TRF", energy / 1e12)
    elseif energy >= 1e9 then
        return string.format("%.2f GRF", energy / 1e9)
    elseif energy >= 1e6 then
        return string.format("%.2f MRF", energy / 1e6)
    elseif energy >= 1e3 then
        return string.format("%.2f kRF", energy / 1e3)
    else
        return string.format("%.0f RF", energy)
    end
end

function battery_api.getTimeToFull()
    local stats = battery_api.getStats()
    if not stats or stats.netFlow <= 0 then
        return nil
    end
    
    local energyNeeded = stats.maxEnergy - stats.energy
    local seconds = energyNeeded / (stats.netFlow * 20)
    
    return seconds
end

function battery_api.getTimeToEmpty()
    local stats = battery_api.getStats()
    if not stats or stats.netFlow >= 0 then
        return nil
    end
    
    local seconds = stats.energy / (math.abs(stats.netFlow) * 20)
    
    return seconds
end

function battery_api.formatTime(seconds)
    if not seconds then
        return "N/A"
    end
    
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    
    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

return battery_api