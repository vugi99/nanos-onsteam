
Package.Require("Config.lua")

IS_WINDOWS = false

SERVER_PATH = nil

function split_str(str, sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end

function GetServerPath()
    local get_working_dir = nil
    if IS_WINDOWS then
        get_working_dir = io.popen("cd")
    else
        get_working_dir = io.popen("pwd")
    end
    local server_path = get_working_dir:read("*a")
    if not IS_WINDOWS then
       server_path = split_str(server_path, "\n")[1]
    end
    io.close(get_working_dir)
    if (server_path and server_path ~= "") then
       local server_path_new = split_str(server_path, "\n")[1]
       server_path_new = '"' .. server_path_new .. '"'
       return server_path_new
    else
        Package.Error("nanos-onsteam : can't get server path")
    end
 end

function IsSteamcmdPathValid()
    local file = io.open(STEAMCMD_PATH)
    if file then
        io.close(file)
        return true
    end
    return false
end

function IsUpdateAvailable()
    Package.Log("nanos-onsteam : Checking for nanos server updates")
    local manifest_file = io.open("steamapps/appmanifest_1686460.acf", "r")
    if manifest_file then
        local manifest_file_content = manifest_file:read("*a")
        io.close(manifest_file)
        local buildid = nil
        local branch = "public"
        local manifest_file_lines = split_str(manifest_file_content, "\n")
        for i, v in ipairs(manifest_file_lines) do
            local manifest_line_wo_spaces = split_str(v, '"')
            for i2, v2 in ipairs(manifest_line_wo_spaces) do
                if v2 == "buildid" then
                    buildid = tonumber(manifest_line_wo_spaces[i2 + 2])
                elseif v2 == "betakey" then
                    branch = manifest_line_wo_spaces[i2 + 2]
                end
            end
        end
        --print("buildid", buildid, "branch", branch)
        if buildid then
            local info_request = io.popen(STEAMCMD_PATH .. ' +login anonymous +app_info_update 1 +app_info_print 1686460 +quit')
            local app_info = info_request:read("*a")
            io.close(info_request)

            local latest_build_for_branch = nil
            local app_info_lines = split_str(app_info, "\n")
            local has_reached_branches = false
            local next_buildid_look = false
            for i, v in ipairs(app_info_lines) do
                local app_info_line_wo_spaces = split_str(v, '"')
                --print(v)
                for i2, v2 in ipairs(app_info_line_wo_spaces) do
                    --print(v2)
                    if has_reached_branches then
                        if next_buildid_look then
                            if v2 == "buildid" then
                                latest_build_for_branch = tonumber(app_info_line_wo_spaces[i2 + 2])
                                next_buildid_look = false
                            end
                        elseif v2 == branch then
                            next_buildid_look = true
                        end
                    elseif v2 == "branches" then
                        has_reached_branches = true
                        --print("has_reached_branches")
                    end
                end
            end
            --print("latest_build_for_branch", latest_build_for_branch)
            if latest_build_for_branch then
                if latest_build_for_branch > buildid then
                    Package.Warn("Nanos server (branch: ".. branch .. ") update available\n Current build : " .. tostring(buildid) .. "\n Latest build : " .. tostring(latest_build_for_branch))
                    return true, branch
                else
                    Package.Log("Nanos server (branch: ".. branch .. ", build: " .. tostring(buildid) .. ") up to date.")
                end
            else
                Package.Error("nanos-onsteam : latest_build_for_branch not found")
            end
        else
            Package.Error("nanos-onsteam : buildid not found")
        end
    else
        Package.Error("nanos-onsteam : steamapps/appmanifest_1686460.acf invalid")
    end
    return false
end

function UpdateServer(branch)
    Package.Log("nanos-onsteam : Updating server")
    local run_str = STEAMCMD_PATH .. " +login anonymous +force_install_dir " .. SERVER_PATH .. " +app_update 1686460 +quit"
    if branch ~= "public" then
        run_str = STEAMCMD_PATH .. " +login anonymous +force_install_dir " .. SERVER_PATH .. ' "+app_update 1686460 -beta ' .. branch .. '" +quit'
    end
    local update_server = io.popen(run_str)
    local update_server_log = update_server:read("*a")
    io.close(update_server)
    local success = false
    local failed_up_to_date = false
    for i, v in ipairs(split_str(update_server_log, "\n")) do
        --print(v)
        if v == "Success! App '1686460' fully installed." then
            success = true
        elseif v == "Success! App '1686460' already up to date." then
            failed_up_to_date = true
        end
    end
    if success then
        Package.Log("nanos-onsteam : Server Updated, stopping the server")
        Server.Stop()
    elseif failed_up_to_date then
        Package.Warn("nanos-onsteam : Can't update server (Retry later)")
    else
        Package.Error("nanos-onsteam : server update failed (or can't check success of the update)")
    end
end

Package.Subscribe("Load", function()
    if File.Exists("NanosWorldServer.exe") then
        --print("IS_WINDOWS = true")
        IS_WINDOWS = true
    end
    local path = GetServerPath()
    --print(path)
    if path then
        SERVER_PATH = path
        if IsSteamcmdPathValid() then
            local is_update, for_branch = IsUpdateAvailable()
            if is_update then
                if AUTO_UPDATE_ON_START then
                    UpdateServer(for_branch)
                end
            end
        else
            Package.Error("nanos-onsteam : Steamcmd path invalid")
        end
    end
end)