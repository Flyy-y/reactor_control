print("Starting Battery Controller...")

if fs.exists("/reactor_control/updater.lua") then
    local updater = dofile("/reactor_control/updater.lua")
    
    updater.setConfig({
        github_user = "Flyy-y",
        github_repo = "reactor_control",
        branch = "main",
        files = {
            "shared/network.lua",
            "shared/protocol.lua",
            "battery/main.lua",
            "battery/battery_api.lua",
            "battery/config.lua"
        }
    })
    
    print("Checking for updates...")
    updater.checkAndUpdate()
else
    print("Updater not found - skipping updates")
end

-- Always wait 5 seconds before starting
print("Waiting 5 seconds before starting...")
sleep(5)

shell.run("/reactor_control/battery/main.lua")