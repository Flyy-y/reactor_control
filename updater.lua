local updater = {}

local config = {
    github_user = "Flyy-y",
    github_repo = "reactor_control",
    branch = "main",
    files = {}
}

function updater.setConfig(newConfig)
    for k, v in pairs(newConfig) do
        config[k] = v
    end
end

local function getGithubUrl(file)
    -- Add cache-busting parameter
    local cacheBuster = "?v=" .. tostring(math.random(100000, 999999))
    return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s%s",
        config.github_user, config.github_repo, config.branch, file, cacheBuster)
end

local function downloadFile(url, destination)
    print("  Downloading: " .. destination)
    local response = http.get(url)
    if response then
        local content = response.readAll()
        response.close()
        
        -- Create directory if it doesn't exist
        local dir = fs.getDir(destination)
        if dir ~= "" and not fs.exists(dir) then
            fs.makeDir(dir)
        end
        
        -- Save file
        local file = fs.open(destination, "w")
        file.write(content)
        file.close()
        return true
    else
        print("  Failed to download: " .. destination)
        return false
    end
end


function updater.checkAndUpdate()
    print("Downloading latest versions of all files...")
    
    local allSuccess = true
    
    -- Always download all files (no hash checking)
    for _, file in ipairs(config.files) do
        local url = getGithubUrl(file)
        local destination = "/reactor_control/" .. file
        
        if not downloadFile(url, destination) then
            allSuccess = false
        end
    end
    
    if allSuccess then
        print("All files updated successfully!")
        print("Restarting in 3 seconds...")
        sleep(3)
        os.reboot()
    else
        print("Some updates failed. Please check your connection.")
        print("Continuing with existing files...")
    end
    
    return allSuccess
end

function updater.forceUpdate()
    -- forceUpdate now does the same as checkAndUpdate (always download everything)
    return updater.checkAndUpdate()
end

return updater