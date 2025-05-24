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
    return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s",
        config.github_user, config.github_repo, config.branch, file)
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

local function getLocalFileHash(path)
    if not fs.exists(path) then
        return nil
    end
    
    local file = fs.open(path, "r")
    local content = file.readAll()
    file.close()
    
    -- Simple hash based on file size and first/last 100 chars
    local hash = tostring(#content)
    if #content > 200 then
        hash = hash .. string.sub(content, 1, 100) .. string.sub(content, -100)
    else
        hash = hash .. content
    end
    
    return hash
end

local function needsUpdate(file)
    local localPath = "/reactor_control/" .. file
    local url = getGithubUrl(file)
    
    -- Get remote file
    local response = http.get(url)
    if not response then
        print("  Cannot check: " .. file)
        return false
    end
    
    local remoteContent = response.readAll()
    response.close()
    
    -- Compare with local
    if not fs.exists(localPath) then
        return true -- File doesn't exist locally
    end
    
    local localFile = fs.open(localPath, "r")
    local localContent = localFile.readAll()
    localFile.close()
    
    return localContent ~= remoteContent
end

function updater.checkAndUpdate()
    print("Checking for updates...")
    
    local filesToUpdate = {}
    local hasUpdates = false
    
    -- Check each file
    for _, file in ipairs(config.files) do
        if needsUpdate(file) then
            table.insert(filesToUpdate, file)
            hasUpdates = true
        end
    end
    
    if not hasUpdates then
        print("No updates available.")
        return false
    end
    
    print("Updates available for " .. #filesToUpdate .. " file(s)")
    print("Downloading updates...")
    
    local allSuccess = true
    for _, file in ipairs(filesToUpdate) do
        local url = getGithubUrl(file)
        local destination = "/reactor_control/" .. file
        
        if not downloadFile(url, destination) then
            allSuccess = false
        end
    end
    
    if allSuccess then
        print("All updates downloaded successfully!")
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
    print("Force updating all files...")
    
    local allSuccess = true
    for _, file in ipairs(config.files) do
        local url = getGithubUrl(file)
        local destination = "/reactor_control/" .. file
        
        if not downloadFile(url, destination) then
            allSuccess = false
        end
    end
    
    if allSuccess then
        print("All files updated successfully!")
    else
        print("Some updates failed.")
    end
    
    return allSuccess
end

return updater