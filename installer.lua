-- Reactor Control System Installer
local function clear()
    term.clear()
    term.setCursorPos(1, 1)
end

local function printHeader()
    clear()
    print("=================================")
    print(" Reactor Control System Installer")
    print("=================================")
    print()
end

local function writeConfig(path, config)
    local file = fs.open(path, "w")
    file.write("return " .. textutils.serialize(config))
    file.close()
end

local function readConfig(path)
    if fs.exists(path) then
        return dofile(path)
    end
    return nil
end

local function downloadFile(url, destination)
    print("Downloading: " .. destination)
    local response = http.get(url)
    if response then
        local content = response.readAll()
        response.close()
        
        local dir = fs.getDir(destination)
        if dir ~= "" and not fs.exists(dir) then
            fs.makeDir(dir)
        end
        
        local file = fs.open(destination, "w")
        file.write(content)
        file.close()
        return true
    end
    return false
end

local function getGithubUrl(file)
    local baseUrl = "https://raw.githubusercontent.com/Flyy-y/reactor_control/main/"
    return baseUrl .. file
end

local function promptChoice(prompt, choices)
    print(prompt)
    for i, choice in ipairs(choices) do
        print(i .. ". " .. choice)
    end
    
    while true do
        write("Choice: ")
        local input = tonumber(read())
        if input and input >= 1 and input <= #choices then
            return input
        end
        print("Invalid choice. Please try again.")
    end
end

local function promptYesNo(prompt)
    print(prompt .. " (y/n)")
    while true do
        local input = read():lower()
        if input == "y" or input == "yes" then
            return true
        elseif input == "n" or input == "no" then
            return false
        end
        print("Please enter 'y' or 'n'")
    end
end

local function promptText(prompt, allowEmpty)
    print(prompt)
    write("> ")
    local input = read()
    if not allowEmpty and input == "" then
        print("Input cannot be empty!")
        return promptText(prompt, allowEmpty)
    end
    return input
end

local function promptPassword(prompt)
    print(prompt)
    write("> ")
    local input = read("*")
    if input == "" then
        print("Password cannot be empty!")
        return promptPassword(prompt)
    end
    return input
end

local function promptNumber(prompt, min, max)
    print(prompt)
    while true do
        write("> ")
        local input = tonumber(read())
        if input and input >= min and input <= max then
            return input
        end
        print("Please enter a number between " .. min .. " and " .. max)
    end
end

local function discoverReactors(privateKey)
    print("\nScanning for existing reactors...")
    
    local modem = peripheral.find("modem")
    if not modem or not modem.isWireless() then
        print("No wireless modem found! Please attach one.")
        return {}
    end
    
    modem.open(100)
    
    local message = {
        type = "request",
        command = "discover_reactors",
        privateKey = privateKey,
        sender = os.getComputerID(),
        timestamp = os.epoch("utc")
    }
    
    modem.transmit(100, 100, message)
    
    local reactors = {}
    local timer = os.startTimer(3)
    
    print("Waiting for responses...")
    
    while true do
        local event, p1, p2, p3, p4 = os.pullEvent()
        
        if event == "timer" and p1 == timer then
            break
        elseif event == "modem_message" then
            local msg = p4
            if type(msg) == "table" and msg.command == "reactor_info" and msg.privateKey == privateKey then
                table.insert(reactors, msg.reactor_id)
                print("Found reactor: ID " .. msg.reactor_id)
            end
        end
    end
    
    modem.close(100)
    
    if #reactors == 0 then
        print("No existing reactors found.")
    else
        print("\nFound " .. #reactors .. " reactor(s)")
    end
    
    return reactors
end

local function getNextReactorId(existingReactors)
    if #existingReactors == 0 then
        return 1
    end
    
    table.sort(existingReactors)
    return existingReactors[#existingReactors] + 1
end

local function installComponent(component, privateKey)
    printHeader()
    print("Installing: " .. component)
    print()
    
    local files = {}
    local config = {}
    
    if component == "Server" then
        files = {
            "shared/network.lua",
            "shared/protocol.lua", 
            "server/main.lua",
            "server/rules.lua",
            "server/storage.lua"
        }
        
        config = {
            privateKey = privateKey,
            modem_channel = 100,
            reactor_channels = {101, 102, 103, 104},
            battery_channel = 110,
            display_channels = {120, 121, 122},
            update_interval = 5,
            heartbeat_timeout = 30,
            safety_rules = {
                max_temperature = 1200,
                max_battery_percent = 80,
                min_coolant_percent = 95,
                max_waste_percent = 5,
                min_fuel_percent = 10,
                max_damage_percent = 0
            },
            auto_control = {
                enabled = true,
                target_burn_rate = 10,
                min_burn_rate = 1,
                max_burn_rate = 50,
                ramp_up_rate = 1,
                ramp_down_rate = 5
            },
            alerts = {
                temperature_warning = 1000,
                temperature_critical = 1100,
                waste_warning = 3,
                fuel_warning = 20,
                battery_warning = 90,
                coolant_warning = 97
            },
            logging = {
                enabled = true,
                max_entries = 1000,
                file = "server.log"
            },
            data_retention = {
                history_size = 500,
                save_interval = 60
            }
        }
        
    elseif component == "Reactor Controller" then
        local existingReactors = discoverReactors(privateKey)
        local reactorId = nil
        
        if #existingReactors > 0 then
            print("\nExisting reactor IDs: " .. table.concat(existingReactors, ", "))
            if promptYesNo("Auto-assign next reactor ID (" .. getNextReactorId(existingReactors) .. ")?") then
                reactorId = getNextReactorId(existingReactors)
            else
                reactorId = promptNumber("Enter reactor ID", 1, 100)
            end
        else
            reactorId = promptNumber("Enter reactor ID (usually start with 1)", 1, 100)
        end
        
        files = {
            "shared/network.lua",
            "shared/protocol.lua",
            "reactor/main.lua",
            "reactor_api.lua"
        }
        
        config = {
            privateKey = privateKey,
            reactor_id = reactorId,
            server_channel = 100,
            broadcast_channel = 100 + reactorId,
            update_interval = 2,
            heartbeat_interval = 15,
            emergency_shutdown = {
                temperature = 1400,
                damage = 25,
                waste_percent = 10
            },
            display = {
                enabled = true,
                update_interval = 0.5
            }
        }
        
    elseif component == "Battery Controller" then
        files = {
            "shared/network.lua",
            "shared/protocol.lua",
            "battery/main.lua",
            "battery/battery_api.lua"
        }
        
        config = {
            privateKey = privateKey,
            server_channel = 100,
            broadcast_channel = 110,
            update_interval = 3,
            heartbeat_interval = 15,
            alerts = {
                low_energy = 10,
                high_energy = 90,
                critical_low = 5,
                critical_high = 95
            },
            display = {
                enabled = true,
                update_interval = 0.5
            }
        }
        
    elseif component == "Display" then
        local displayId = promptNumber("Enter display ID", 1, 10)
        
        files = {
            "shared/network.lua",
            "shared/protocol.lua",
            "display/main.lua",
            "display/ui.lua"
        }
        
        config = {
            privateKey = privateKey,
            display_id = displayId,
            server_channel = 100,
            listen_channel = 119 + displayId,
            update_interval = 2,
            request_timeout = 5,
            monitor = {
                side = "auto",
                text_scale = 0.5
            },
            display = {
                show_alerts = true,
                max_alerts = 5,
                show_graphs = true,
                graph_history = 50
            },
            colors = {
                background = colors.black,
                text = colors.white,
                header = colors.yellow,
                active = colors.lime,
                inactive = colors.red,
                warning = colors.orange,
                critical = colors.red,
                good = colors.lime,
                border = colors.gray
            }
        }
    end
    
    -- Download files
    print("\nDownloading files...")
    for _, file in ipairs(files) do
        local url = getGithubUrl(file)
        local destination = "/reactor_control/" .. file
        
        if not downloadFile(url, destination) then
            print("Failed to download: " .. file)
            print("Please check your internet connection and GitHub settings.")
            return false
        end
    end
    
    -- Write config
    local configPath = ""
    if component == "Server" then
        configPath = "/reactor_control/server/config.lua"
    elseif component == "Reactor Controller" then
        configPath = "/reactor_control/reactor/config.lua"
    elseif component == "Battery Controller" then
        configPath = "/reactor_control/battery/config.lua"
    elseif component == "Display" then
        configPath = "/reactor_control/display/config.lua"
    end
    
    print("\nWriting configuration...")
    writeConfig(configPath, config)
    
    -- Create startup file
    local startupContent = ""
    if component == "Server" then
        startupContent = [[
print("Starting Reactor Control Server...")
shell.run("/reactor_control/server/main.lua")
]]
    elseif component == "Reactor Controller" then
        startupContent = [[
print("Starting Reactor Controller...")
shell.run("/reactor_control/reactor/main.lua")
]]
    elseif component == "Battery Controller" then
        startupContent = [[
print("Starting Battery Controller...")
shell.run("/reactor_control/battery/main.lua")
]]
    elseif component == "Display" then
        startupContent = [[
print("Starting Display...")
shell.run("/reactor_control/display/main.lua")
]]
    end
    
    if promptYesNo("\nCreate startup file for automatic launch?") then
        local file = fs.open("/startup.lua", "w")
        file.write(startupContent)
        file.close()
        print("Startup file created.")
    end
    
    return true
end

-- Main installer
local function main()
    printHeader()
    
    print("This installer will set up the Reactor Control System")
    print("on this computer.")
    print()
    
    -- Check for wireless modem
    local modem = peripheral.find("modem")
    if not modem or not modem.isWireless() then
        print("WARNING: No wireless modem detected!")
        print("Please attach a wireless modem for the system to work.")
        print()
        if not promptYesNo("Continue anyway?") then
            return
        end
    end
    
    -- Get or generate private key
    local privateKey = ""
    local existingConfig = readConfig("/reactor_control/config.lua")
    
    if existingConfig and existingConfig.privateKey then
        print("Found existing private key.")
        if promptYesNo("Use existing private key?") then
            privateKey = existingConfig.privateKey
        else
            privateKey = promptPassword("Enter private key (shared secret for all components)")
        end
    else
        if promptYesNo("Generate random private key?") then
            privateKey = tostring(math.random(100000, 999999))
            print("Generated private key: " .. privateKey)
            print("IMPORTANT: Write this down! You'll need it for other components.")
            print()
            print("Press any key to continue...")
            os.pullEvent("key")
        else
            privateKey = promptPassword("Enter private key (shared secret for all components)")
        end
    end
    
    -- Save private key
    writeConfig("/reactor_control/config.lua", {privateKey = privateKey})
    
    -- Choose component
    local components = {
        "Server",
        "Reactor Controller",
        "Battery Controller",
        "Display"
    }
    
    printHeader()
    local choice = promptChoice("Select component to install:", components)
    
    if installComponent(components[choice], privateKey) then
        printHeader()
        print("Installation complete!")
        print()
        print("Component: " .. components[choice])
        print("Private key: " .. string.rep("*", #privateKey))
        print()
        
        if promptYesNo("Start the component now?") then
            shell.run("/startup.lua")
        else
            print("\nTo start manually, run: /startup.lua")
        end
    else
        print("\nInstallation failed!")
    end
end

main()