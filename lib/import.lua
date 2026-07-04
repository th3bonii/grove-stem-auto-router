-- Grove Stem Auto-Router / lib/import.lua
-- Stem file scanning, name normalization, track matching, media insertion
-- Depends on: R.Config, R.MatchingEngine, R.Fuzzy

---@diagnostic disable: lowercase-global

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

    --- Normalize a stem filename into a category and tokens.
    -- Delegates to the matching-engine's tokenize + resolve internally.
    -- Kept for backward compatibility (used by overflow.lua dispatch).
    -- @param name string — stem filename
    -- @param config table — route_map config (unused, kept for signature compat)
    -- @return string — category (first alias match, or first non-ignored token)
    -- @return table — filtered token array (before alias resolution)
    function R.Import.normalize(name, config)
        local tokens = R.MatchingEngine.tokenize(name)
        if #tokens == 0 then
            local base = name:gsub("%.[^%.]+$", "")
            return base:lower(), {}
        end
        local resolved, first_alias = R.MatchingEngine.resolve(tokens, config)
        if first_alias then return first_alias, tokens end
        return tokens[1], tokens
    end

    --- Match a stem against available tracks using the matching engine.
    -- New entry point that replaces the old match()'s role.
    -- Delegates to R.MatchingEngine.match() with the full priority chain:
    --   calibrated GUID → token-intersection → fuzzy → orphan/nil
    -- @param stem_name string — original stem filename
    -- @param tracks table — array of { track, name, guid }
    -- @param config table — route_map config
    -- @param guid_map table|nil — { guid → track } from Calibration.get_track_map()
    -- @return reaper.MediaTrack|nil — matched track
    -- @return string|nil — track display name
    -- @return string|nil — match method ("calibrated", "token-intersection", "fuzzy", or nil)
    function R.Import.match_stem(stem_name, tracks, config, guid_map)
        if not R.MatchingEngine or not R.MatchingEngine.match then
            reaper.ShowConsoleMsg("Grove: MatchingEngine not loaded. Falling back to no match.\n")
            return nil, nil, nil
        end
        return R.MatchingEngine.match(stem_name, tracks, config, guid_map)
    end

    --- @deprecated Legacy exact-name matcher.
    -- Replaced by match_stem() which delegates to MatchingEngine.
    -- Kept for backward compatibility with any external callers.
    -- Will be removed in a future version.
    function R.Import.match(category, tracks, guid_map, stem_tokens)
        local function find_exact(name)
            local n = name:lower()
            local m = {}
            for _, t in ipairs(tracks) do
                if (t.name or ""):lower() == n then m[#m + 1] = t end
            end
            return m
        end

        -- try the aliased category first
        local matches = find_exact(category)
        -- if no match, try each original stem token
        if #matches == 0 and stem_tokens then
            for _, token in ipairs(stem_tokens) do
                matches = find_exact(token)
                if #matches > 0 then break end
            end
        end
        -- try removing numbers from tokens (for "Lead- 02-06" → "Lead")
        if #matches == 0 and stem_tokens then
            for _, token in ipairs(stem_tokens) do
                local clean = token:match("^[%a]+") or token
                if clean ~= token then
                    matches = find_exact(clean)
                    if #matches > 0 then break end
                end
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

    --- Insert a media file onto a REAPER track as a new item+take.
    -- Position defaults to 0.0, or after the last item if no explicit position given.
    -- Config is optional; when provided with color_stems_by_track=true, the item
    -- inherits the track's custom color.
    -- @param path string — full path to the audio file
    -- @param track reaper.MediaTrack — target track
    -- @param position number|nil — explicit item position (optional)
    -- @param config table|nil — route_map config for color inheritance (optional)
    -- @return reaper.MediaItem|nil — the created item, or nil on failure
    function R.Import.insert_media(path, track, position, config)
        if not track then
            reaper.ShowConsoleMsg("Grove: insert_media called with nil track for " .. (path or "?") .. "\n")
            return nil
        end
        -- diagnostic: does the file exist?
        local exists = reaper.File_Exists and reaper.File_Exists(path)
        if exists == false then
            reaper.ShowConsoleMsg("Grove: FILE DOES NOT EXIST: " .. path .. "\n")
        end

        local basename = path:match("([^/]+)%.[^%.]+$") or path

        -- item position: explicit, or auto after last item on track
        local item_pos = position
        if not item_pos then
            item_pos = 0
            local ic = reaper.CountTrackMediaItems(track)
            if ic > 0 then
                local last = reaper.GetTrackMediaItem(track, ic - 1)
                local ok_p, pos = pcall(reaper.GetMediaItemInfo_Value, last, "D_POSITION")
                local ok_l, len = pcall(reaper.GetMediaItemInfo_Value, last, "D_LENGTH")
                if ok_p and ok_l and pos and len then
                    item_pos = pos + len
                end
            end
        end

        -- Create empty item + take
        local item = reaper.AddMediaItemToTrack(track)
        if not item then
            reaper.ShowConsoleMsg("Grove: Failed to create media item for " .. path .. "\n")
            return nil
        end
        pcall(reaper.SetMediaItemInfo_Value, item, "D_POSITION", item_pos)
        pcall(reaper.SetMediaItemInfo_Value, item, "D_LENGTH", 0)

        local take = reaper.AddTakeToMediaItem(item)
        if not take then
            reaper.ShowConsoleMsg("Grove: Failed to create take for " .. path .. "\n")
            return item
        end

        -- Set take name
        pcall(reaper.GetSetMediaItemTakeInfo_String, take, "P_NAME", basename, true)

        -- Create PCM_source and assign it to the take
        local src = reaper.PCM_Source_CreateFromFile(path)
        if src then
            local len = reaper.GetMediaSourceLength(src) or 0

            -- Use SetMediaItemTake_Source (dedicated function, available in REAPER 5+)
            local ok_set = false
            if reaper.SetMediaItemTake_Source then
                ok_set = reaper.SetMediaItemTake_Source(take, src)
            end

            if not ok_set then
                reaper.ShowConsoleMsg("Grove: SetMediaItemTake_Source failed for " .. basename .. "\n")
            end

            if len > 0 then
                pcall(reaper.SetMediaItemInfo_Value, item, "D_LENGTH", len)
                pcall(reaper.SetMediaItemInfo_Value, item, "D_POSITION", item_pos)
            end
            reaper.ShowConsoleMsg("Grove: OK " .. basename .. " → " .. len .. "s\n")
        else
            reaper.ShowConsoleMsg("Grove: PCM_Source_CreateFromFile FAILED for: " .. path .. "\n")
        end

        -- Color inheritance: read track custom color and apply to item
        if config and config.color_stems_by_track then
            local track_color = reaper.GetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR")
            if track_color and track_color ~= 0 then
                pcall(reaper.SetMediaItemInfo_Value, item, "I_CUSTOMCOLOR", track_color)
            end
        end

        pcall(reaper.UpdateItemInProject, item)
        return item
    end
end
