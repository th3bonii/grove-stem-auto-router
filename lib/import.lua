-- Grove Stem Auto-Router / lib/import.lua
-- Stem file scanning, name normalization, track matching, media insertion
-- Depends on: R.Config

return function(R)
    R.Import = {}

    function R.Import.scan(dir)
        dir = dir:gsub("\\", "/")
        if dir:sub(-1) ~= "/" then dir = dir .. "/" end
        local stems = {}
        local i = 0
        while true do
            local filename = reaper.EnumerateFiles(dir, i)
            if not filename or filename == "" then break end
            local ext = filename:lower():match("%.([^%.]+)$")
            if ext == "wav" or ext == "flac" or ext == "mp3" then
                stems[#stems + 1] = {
                    path = dir .. filename:gsub("\\", "/"),
                    name = filename
                }
            end
            i = i + 1
        end
        return stems
    end

    function R.Import.normalize(name, config)
        local base = name:gsub("%.[^%.]+$", "")
        local cleaned = base:gsub("[_%-%.]", " "):lower()
        local tokens = {}
        for token in cleaned:gmatch("%S+") do
            tokens[#tokens + 1] = token
        end
        local ignore = R.Config.get_ignore_set()
        local filtered = {}
        for _, token in ipairs(tokens) do
            if not ignore[token] then
                filtered[#filtered + 1] = token
            end
        end
        local alias_map = R.Config.get_alias_map()
        for _, token in ipairs(filtered) do
            local mapped = alias_map[token]
            if mapped then return mapped end
        end
        if #filtered > 0 then return filtered[1] end
        return base:lower()
    end

    function R.Import.match(category, tracks, guid_map)
        local cat_lower = category:lower()
        local matches = {}
        for _, t in ipairs(tracks) do
            local tname = (t.name or ""):lower()
            if tname == cat_lower then
                matches[#matches + 1] = t
            end
        end
        if #matches == 0 then return nil, nil end
        if #matches == 1 then return matches[1].track, matches[1].name end
        if guid_map then
            for _, t in ipairs(matches) do
                local ok, guid = pcall(reaper.GetTrackGUID, t.track)
                if ok and guid and guid_map[guid] then
                    return t.track, t.name
                end
            end
        end
        return matches[1].track, matches[1].name
    end

    function R.Import.insert_media(path, track)
        local item = reaper.AddMediaItemToTrack(track)
        if not item then
            reaper.ShowConsoleMsg("Grove: Failed to create media item for " .. path .. "\n")
            return nil
        end
        reaper.GetSetMediaItemInfo(item, "D_POSITION", 0.0)
        local take = reaper.AddTakeToMediaItem(item)
        if not take then
            reaper.ShowConsoleMsg("Grove: Failed to create take for " .. path .. "\n")
            return item
        end
        local basename = path:match("([^/]+)%.[^%.]+$") or path
        reaper.GetSetMediaItemTakeInfo(take, "P_NAME", basename)
        local src = reaper.PCM_Source_CreateFromFile(path)
        if src then
            reaper.GetSetMediaItemTakeInfo(take, "P_SOURCE", src)
            local len = reaper.GetMediaSourceLength(src)
            if len then reaper.GetSetMediaItemInfo(item, "D_LENGTH", len) end
        end
        reaper.UpdateItemInProject(item)
        return item
    end
end
