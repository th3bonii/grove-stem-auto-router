-- Grove Stem Auto-Router / lib/overflow.lua
-- Overflow dispatch: lanes or new track, with API detection
-- Depends on: R.Config, R.Import

return function(R)
    R.Overflow = {}

    R.Overflow._has_fixed_lanes = nil

    function R.Overflow._check_lanes_api()
        if R.Overflow._has_fixed_lanes ~= nil then return R.Overflow._has_fixed_lanes end
        if reaper.APIExists then
            R.Overflow._has_fixed_lanes = reaper.APIExists("SetTrackLaneComping")
        else
            local t = reaper.GetTrack(0, 0)
            if t then
                R.Overflow._has_fixed_lanes = pcall(reaper.SetTrackLaneComping, t, 0)
            else
                R.Overflow._has_fixed_lanes = false
            end
        end
        return R.Overflow._has_fixed_lanes
    end

    function R.Overflow.dispatch(stem, track, config, idx)
        local category = R.Import.normalize(stem.name, config)
        local behavior = R.Config.get_overflow(category)
        local item_count = 0
        while reaper.GetTrackMediaItem(track, item_count) do item_count = item_count + 1 end
        if behavior == "lanes" and R.Overflow._check_lanes_api() then
            local max_lanes = config.max_lanes_per_track or 0
            if max_lanes == 0 or item_count < max_lanes then
                R.Overflow._to_lane(stem, track)
            else
                R.Overflow._to_new_track(stem, track)
            end
        else
            R.Overflow._to_new_track(stem, track)
        end
    end

    function R.Overflow._to_lane(stem, track)
        reaper.SetTrackLaneComping(track, 0)
        R.Import.insert_media(stem.path, track)
    end

    function R.Overflow._to_new_track(stem, category_track)
        local track_idx = -1
        for i = 0, reaper.CountTracks(0) - 1 do
            if reaper.GetTrack(0, i) == category_track then track_idx = i; break end
        end
        reaper.InsertTrackAtIndex(track_idx + 1, true)
        local new_track = reaper.GetTrack(0, track_idx + 1)
        reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 0)
        local _, orig_name = reaper.GetTrackName(category_track, "")
        local stem_name = stem.name:gsub("%.[^%.]+$", "")
        reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", orig_name .. " - " .. stem_name, true)
        R.Import.insert_media(stem.path, new_track)
    end
end
