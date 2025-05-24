print("Starting Reactor Controller...")

if fs.exists("/reactor_control/updater.lua") then
    local updater = dofile("/reactor_control/updater.lua")
    
    updater.setConfig({
        github_user = "Flyy-y",
        github_repo = "reactor_control",
        branch = "main",
        files = {
            "shared/network.lua",
            "shared/protocol.lua",
            "reactor/main.lua",
            "reactor/config.lua"
        }
    })
    
    print("Checking for updates...")
    updater.checkAndUpdate()
end

-- Wait 5 seconds before starting
print("Waiting 5 seconds before starting...")
sleep(5)

shell.run("/reactor_control/reactor/main.lua")