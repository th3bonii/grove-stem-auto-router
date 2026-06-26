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
        for guid in pairs(guid_map) do
            local ok, track = pcall(reaper.BR_GetMediaTrackByGUID, 0, guid)
            if ok and track then
                valid[guid] = track
            else
                stale[#stale + 1] = guid
            end
        end
        if #stale > 0 then
            reaper.ShowConsoleMsg("Grove: " .. #stale .. " stale GUID(s). Falling back to name match.\n")
        end
        return valid, stale
    end

    function R.Calibration.save(tracks)
        local parts = {}
        for _, track in ipairs(tracks) do
            local ok, guid = pcall(reaper.GetTrackGUID, track)
            if ok and guid then
                parts[#parts + 1] = '"' .. guid .. '"'
            end
        end
        if #parts == 0 then
            reaper.ShowConsoleMsg("Grove: No track GUIDs to save.\n")
            return 0
        end
        local json = "[" .. table.concat(parts, ",") .. "]"
        reaper.SetProjExtState(0, "GROVE_STEMS", "TargetGUIDs", json)
        reaper.ShowConsoleMsg("Grove: Calibration saved " .. #parts .. " GUID(s).\n")
        return #parts
    end

    function R.Calibration.get_count()
        local guids = R.Calibration.load()
        if not guids then return 0 end
        local count = 0
        for _ in pairs(guids) do count = count + 1 end
        return count
    end
end
