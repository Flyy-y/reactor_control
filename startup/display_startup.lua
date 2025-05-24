print("Starting Display Controller...")

-- Check if we just updated
if fs.exists("/.just_updated") then
    print("Just updated - skipping update check")
    fs.delete("/.just_updated")
else
    if fs.exists("/reactor_control/updater.lua") then
        local updater = dofile("/reactor_control/updater.lua")
        
        updater.setConfig({
            github_user = "Flyy-y",
            github_repo = "reactor_control",
            branch = "main",
            files = {
                "shared/network.lua",
                "shared/protocol.lua",
                "display/main.lua",
                "display/ui.lua"
            }
        })
        
        print("Checking for updates...")
        updater.checkAndUpdate()
    else
        print("Updater not found - skipping updates")
    end
end

-- Always wait 5 seconds before starting
print("Waiting 5 seconds before starting...")
sleep(5)

shell.run("/reactor_control/display/main.lua")