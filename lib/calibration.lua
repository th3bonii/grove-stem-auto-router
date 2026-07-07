-- Grove Stem Auto-Router / lib/calibration.lua
-- GUID-based track calibration: save, load, validate
-- Depends on: JSON (from lib/json.lua)

return function(R, JSON)
    R.Calibration = {}

    function R.Calibration.load()
        local function _get()
            return reaper.GetProjExtState(0, "GROVE_STEMS", "TargetGUIDs")
        end
        local ok, ret1, ret2 = pcall(_get)
        if not ok then return nil end
        local json_str
        if type(ret1) == "boolean" then
            json_str = ret2
        else
            json_str = ret1
        end
        if type(json_str) ~= "string" or json_str == "" then return nil end
        local guids, err = JSON.parse(json_str)
        if not guids or type(guids) ~= "table" then
            reaper.ShowConsoleMsg("Grove: Invalid calibration data in ExtState.\n")
            return nil
        end
        local guid_map = {}
        for _, guid in ipairs(guids) do
            if type(guid) == "string" and #guid > 0 then
                guid_map[guid] = true
            end
        end
        if not next(guid_map) then return nil end
        return guid_map
    end

    function R.Calibration.validate(guid_map)
        local valid = {}
        local stale = {}
        local fallback = false

        -- Try SWS BR_GetMediaTrackByGUID first (fast, direct lookup)
        if reaper.BR_GetMediaTrackByGUID then
            for guid in pairs(guid_map) do
                local ok, track = pcall(reaper.BR_GetMediaTrackByGUID, 0, guid)
                if ok and track then
                    valid[guid] = track
                else
                    stale[#stale + 1] = guid
                end
            end
        else
            -- Fallback: enumerate all tracks and compare GUIDs
            -- Works without SWS Extension (native REAPER API only)
            fallback = true
            reaper.ShowConsoleMsg("Grove: SWS not available — using brute-force GUID validation.\n")

            -- Build a reverse map once: guid → track for all current tracks
            local live_map = {}
            for i = 0, reaper.CountTracks(0) - 1 do
                local track = reaper.GetTrack(0, i)
                local ok_g, guid = pcall(reaper.GetTrackGUID, track)
                if ok_g and guid and guid ~= "" then
                    live_map[guid] = track
                end
            end

            for guid in pairs(guid_map) do
                if live_map[guid] then
                    valid[guid] = live_map[guid]
                else
                    stale[#stale + 1] = guid
                end
            end
        end

        if #stale > 0 then
            reaper.ShowConsoleMsg("Grove: " .. #stale .. " stale GUID(s). "
                .. (fallback and "Track removed or renamed." or "Falling back to name match.") .. "\n")
        end
        return valid, stale
    end

function R.Calibration.save(tracks)
  local guid_list = {}
  local guid_set = {}
  for _, track in ipairs(tracks) do
    if not track then
      reaper.ShowConsoleMsg("Grove: Skipping nil track in calibration save.\n")
    else
      local ok, guid = pcall(reaper.GetTrackGUID, track)
      if not ok then ok = false end
      if not ok or not guid then
        reaper.ShowConsoleMsg("Grove: Skipping track with missing GUID.\n")
      elseif guid_set[guid] then
        reaper.ShowConsoleMsg("Grove: Ignoring duplicate GUID during calibration save: " .. guid .. "\n")
      else
        guid_set[guid] = true
        guid_list[#guid_list + 1] = guid
      end
    end
  end
        if #guid_list == 0 then
            reaper.ShowConsoleMsg("Grove: No track GUIDs to save.\n")
            return 0
        end
        local json = R.JSON.stringify(guid_list)
        reaper.SetProjExtState(0, "GROVE_STEMS", "TargetGUIDs", json)
        reaper.ShowConsoleMsg("Grove: Calibration saved " .. #guid_list .. " GUID(s).\n")
        return #guid_list
    end

    function R.Calibration.get_count()
        local guids = R.Calibration.load()
        if not guids then return 0 end
        local count = 0
        for _ in pairs(guids) do count = count + 1 end
        return count
    end

    --- Return a { guid → track } map of currently valid calibrated tracks.
    -- Loads calibration data from ExtState, validates it, and returns
    -- only the GUIDs that still point to existing REAPER tracks.
    -- Returns nil if no calibration data exists or all GUIDs are stale.
    -- Used by MatchingEngine as the primary track set for calibrated matching.
    -- @return table|nil — { guid_string → MediaTrack } or nil
    function R.Calibration.get_track_map()
        local raw = R.Calibration.load()
        if not raw then return nil end
        local valid, _ = R.Calibration.validate(raw)
        return valid  -- valid is { guid → track } from validate()
    end
end
