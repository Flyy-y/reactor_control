print("Starting Battery Controller...")

if fs.exists("/reactor_control/updater.lua") then
    os.loadAPI("/reactor_control/updater.lua")
    
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
end

shell.run("/reactor_control/battery/main.lua")