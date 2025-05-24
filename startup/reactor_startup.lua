print("Starting Reactor Controller...")

if fs.exists("/reactor_control/updater.lua") then
    os.loadAPI("/reactor_control/updater.lua")
    
    updater.setConfig({
        github_user = "Flyy-y",
        github_repo = "reactor_control",
        branch = "main",
        files = {
            "shared/network.lua",
            "shared/protocol.lua",
            "reactor/main.lua",
            "reactor_api.lua",
            "reactor/config.lua"
        }
    })
    
    print("Checking for updates...")
    updater.checkAndUpdate()
end

shell.run("/reactor_control/reactor/main.lua")