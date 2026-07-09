-- Grove Stem Auto-Router / lib/overflow.lua
-- Overflow dispatch: lanes or new track, with API detection
-- Depends on: R.Config, R.Import

return function(R)
    R.Overflow = {}

    R.Overflow._has_fixed_lanes = nil

    --- Detect the best available lanes API.
    -- Priority: REAPER 7+ SetMediaTrackLanes → SetTrackLaneComping → free mode
    -- Caches result so API is only detected once per session.
    -- @return string — "lanes7", "lanecomping", or "freemode"
    function R.Overflow._check_lanes_api()
        if R.Overflow._has_fixed_lanes ~= nil then return R.Overflow._has_fixed_lanes end

        -- Check for REAPER 7+ native Fixed Lanes API
        if reaper.APIExists and reaper.APIExists("SetMediaTrackLanes") then
            R.Overflow._has_fixed_lanes = "lanes7"
            reaper.ShowConsoleMsg("Grove: Using REAPER 7+ Fixed Lanes API\n")
            return R.Overflow._has_fixed_lanes
        end

        -- Check for REAPER 6+ SetTrackLaneComping
        if reaper.APIExists and reaper.APIExists("SetTrackLaneComping") then
            R.Overflow._has_fixed_lanes = "lanecomping"
            reaper.ShowConsoleMsg("Grove: Using SetTrackLaneComping (REAPER 6+)\n")
            return R.Overflow._has_fixed_lanes
        end

        -- Check by direct function reference (older REAPER builds)
        if reaper.SetTrackLaneComping ~= nil then
            R.Overflow._has_fixed_lanes = "lanecomping"
            reaper.ShowConsoleMsg("Grove: Using SetTrackLaneComping (direct ref)\n")
            return R.Overflow._has_fixed_lanes
        end

        -- Fallback to free item positioning
        R.Overflow._has_fixed_lanes = "freemode"
        reaper.ShowConsoleMsg("Grove: Using free item positioning (no lanes API)\n")
        return R.Overflow._has_fixed_lanes
    end

    --- Dispatch an overflow stem to a lane or new track.
    -- Resolves behavior via R.Config.get_overflow(category) which checks:
    --   1. Category-level overflow_behavior in route_map.json
    --   2. Root-level overflow_behavior (fallback)
    -- This way categories like sub_bass/drums that specify "new_track" are
    -- respected, while the global "lanes" default still applies.
    -- The GUI can override the root-level default via config.overflow_behavior.
    -- @param stem table — stem record { path, name }
    -- @param track reaper.MediaTrack — the matched track receiving overflow
    -- @param config table — route_map config
    -- @param category string|nil — stem category for per-category override
    function R.Overflow.dispatch(stem, track, config, category)
        local behavior = category and R.Config.get_overflow(category) or config.overflow_behavior or "lanes"
        local item_count = 0
        while reaper.GetTrackMediaItem(track, item_count) do item_count = item_count + 1 end

        if behavior == "lanes" then
            local max_lanes = (config and config.max_lanes_per_track) or 0
            if max_lanes > 0 and item_count >= max_lanes then
                R.Overflow._to_new_track(stem, track)
            else
                R.Overflow._to_lane(stem, track)
            end
        else
            R.Overflow._to_new_track(stem, track)
        end
    end

    --- Place a stem as a new lane on an existing track.
    -- Uses the best available lanes API for the current REAPER version.
    -- @param stem table — stem record
    -- @param track reaper.MediaTrack — target track
    function R.Overflow._to_lane(stem, track)
        local api = R.Overflow._check_lanes_api()

        local prev_freemode = reaper.GetMediaTrackInfo_Value(track, "I_FREEMODE")

        if api == "lanes7" then
            -- REAPER 7+ native Fixed Lanes: enable then place item
            pcall(reaper.SetMediaTrackLanes, track, true)
        elseif api == "lanecomping" then
            -- REAPER 6+ lane comping: free mode + comping
            reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", 1)
            pcall(reaper.SetTrackLaneComping, track, 0)
        else
            -- Free item positioning (fallback)
            reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", 1)
        end

        -- Overflow item starts at the same position as the first (main) item on the track
        local pos = 0
        local first = reaper.GetTrackMediaItem(track, 0)
        if first then
            local ok, p = pcall(reaper.GetMediaItemInfo_Value, first, "D_POSITION")
            if ok and p then pos = p end
        end

        R.Import.insert_media(stem.path, track, pos)

        -- Restore previous I_FREEMODE after inserting the overflow item
        reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", prev_freemode)
    end

    --- Walk the I_FOLDERDEPTH chain upward from a tracked track to find
    -- the folder it belongs to, then return the index after the last
    -- track inside that folder (where new overflow tracks should be inserted).
    -- @param category_track reaper.MediaTrack — the matched track
    -- @return int — insert index, or -1 if not inside any folder
    function R.Overflow._get_parent_folder_last_idx(category_track)
        local track_idx = -1
        for i = 0, reaper.CountTracks(0) - 1 do
            if reaper.GetTrack(0, i) == category_track then
                track_idx = i
                break
            end
        end
        if track_idx < 0 then return track_idx end

        -- Walk backwards to find the folder start (I_FOLDERDEPTH = 1)
        local folder_start = -1
        local depth = 0
        for i = track_idx, 0, -1 do
            local t = reaper.GetTrack(0, i)
            local fd = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
            -- Skip the matched track's own I_FOLDERDEPTH when it's a folder
            -- closer (-1): the -1 means "last track inside folder" but the
            -- track IS inside that folder, so we must ignore its own fd to
            -- find the parent folder start going backward.
            if i ~= track_idx or fd ~= -1 then
                depth = depth + fd
            end
            if depth >= 1 then
                folder_start = i
                break
            end
        end
        if folder_start < 0 then return -1 end  -- not in a folder

        -- Walk forward from folder_start to find the last track at depth > 0
        -- (the last track inside the folder, before the -1 sentinel)
        local last_inside = folder_start
        local running_depth = 1
        for i = folder_start + 1, reaper.CountTracks(0) - 1 do
            local t = reaper.GetTrack(0, i)
            local fd = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
            running_depth = running_depth + fd
            if running_depth <= 0 then break end  -- exited the folder
            last_inside = i
        end

        -- Return the index AFTER the last track inside the folder
        return last_inside + 1
    end

    --- Create a new track for overflow, placed inside the parent folder
    -- (if the matched track is in a folder) or directly after the matched track.
    -- @param stem table — stem record
    -- @param category_track reaper.MediaTrack — the matched track
    function R.Overflow._to_new_track(stem, category_track)
        local insert_idx = R.Overflow._get_parent_folder_last_idx(category_track)
        if insert_idx < 0 then
            -- No parent folder found: insert directly after the matched track
            for i = 0, reaper.CountTracks(0) - 1 do
                if reaper.GetTrack(0, i) == category_track then
                    insert_idx = i + 1
                    break
                end
            end
            if insert_idx <= 0 then insert_idx = reaper.CountTracks(0) end
        end

        reaper.InsertTrackAtIndex(insert_idx, true)
        local new_track = reaper.GetTrack(0, insert_idx)
        reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 0)

        local _, orig_name = reaper.GetTrackName(category_track, "")
        local stem_name = stem.name:gsub("%.[^%.]+$", "")
        reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", orig_name .. " - " .. stem_name, true)

        R.Import.insert_media(stem.path, new_track)
    end
end
