-- Grove Stem Auto-Router / lib/orphan.lua
-- Orphan stem handling: collect, display, auto-insert as new tracks
-- Depends on: R.Import (for insert_media)

return function(R)
    R.Orphan = {}

    --- Collect unmatched stems from assignments.
    -- Builds a GUI-friendly structure with display info and selection state.
    -- @param stems table — raw stem list from R.Import.scan()
    -- @param assignments table — { idx → { track, name, method, category } } from run_matching()
    -- @return table — { orphans[], matched_count, orphan_count }
    function R.Orphan.collect(stems, assignments)
        local orphans = {}
        local matched_count = 0
        for idx, stem in ipairs(stems) do
            local a = assignments[idx]
            if a and a.track then
                matched_count = matched_count + 1
            else
                local display = stem.display_name or stem.name
                local cat = "(unknown)"
                if a and a.category then cat = a.category end
                orphans[#orphans + 1] = {
                    stem     = stem,
                    index    = idx,
                    display  = display,
                    category = cat,
                    reason   = a and a.reason or "no match in any track",
                    selected = false,
                }
            end
        end
        return {
            orphans       = orphans,
            matched_count = matched_count,
            orphan_count  = #orphans,
        }
    end

--- Insert only selected orphans as new tracks.
    -- Resets selection after insertion.
    -- @param orphans table — from collect().orphans
    -- @param config table — route_map config
    -- @return int — count of tracks created
    function R.Orphan.insert_selected(orphans, config)
        local created = 0
        for _, orphan in ipairs(orphans) do
            if orphan.selected then
                R.Orphan._create_track_from_orphan(orphan, config)
                created = created + 1
                orphan.selected = false
            end
        end
        return created
    end

    --- Internal: create a REAPER track from an orphan stem.
    -- Places the new track at the end of the matching category's folder,
    -- or at the project end if no category is known.
    -- @param orphan table — single orphan entry from collect()
    -- @param config table — route_map config (unused in current impl, reserved)
    -- @return reaper.MediaTrack — the newly created track
    function R.Orphan._create_track_from_orphan(orphan, config)
        local target_idx = reaper.CountTracks(0)  -- default: end of project
        local stem_name = orphan.stem.name:gsub("%.[^%.]+$", "")
        local category = orphan.category

        -- Try to find a track matching the category and place after its folder
        if category and category ~= "(unknown)" then
            local last_idx = -1
            for i = 0, reaper.CountTracks(0) - 1 do
                local track = reaper.GetTrack(0, i)
                local _, nm = reaper.GetTrackName(track, "")
                if nm:lower() == category:lower() then
                    last_idx = i
                elseif nm:lower():find(category:lower(), 1, true) then
                    last_idx = i
                end
            end
            if last_idx >= 0 then
                target_idx = last_idx + 1
            end
        end

        reaper.InsertTrackAtIndex(target_idx, true)
        local new_track = reaper.GetTrack(0, target_idx)
        if new_track then
            reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 0)
            reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", stem_name, true)
            R.Import.insert_media(orphan.stem.path, new_track)
        end
        return new_track
    end

    --- Export orphans as JSON for the AI proxy.
    -- Writes orphans.json with stem list and available tracks,
    -- and ai_config.json with the current AI configuration.
    -- @param orphan_data table — from collect()
    -- @param tracks table — { track, name, guid }[]
    -- @param script_dir string — REAPER script directory path
    -- @param config table — route_map config (unused in signature, reads from R.Config)
    function R.Orphan.export_for_ai(orphan_data, tracks, script_dir, config)
        local orphans_json = {
            orphans = {},
            available_tracks = {},
        }

        for _, o in ipairs(orphan_data.orphans) do
            orphans_json.orphans[#orphans_json.orphans + 1] = {
                filename = o.stem.name,
                path = o.stem.path,
                category = o.category,
            }
        end

        for _, t in ipairs(tracks) do
            orphans_json.available_tracks[#orphans_json.available_tracks + 1] = t.name
        end

        -- Save orphans.json
        local json_str = R.JSON.stringify(orphans_json)
        local file, err = io.open(script_dir .. "orphans.json", "w")
        if file then
            file:write(json_str)
            file:close()
        end

        -- Save ai_config.json for the Python proxy
        local ai_cfg = R.Config.get_ai_config()
        local ai_cfg_json = R.JSON.stringify(ai_cfg)
        local cfg_file, _ = io.open(script_dir .. "ai_config.json", "w")
        if cfg_file then
            cfg_file:write(ai_cfg_json)
            cfg_file:close()
        end
    end

    --- Check if AI mapping results are available from the proxy.
    -- Removes the mapping.json file after reading to avoid re-processing.
    -- @param script_dir string — REAPER script directory path
    -- @param orphans table — orphan data from collect()
    -- @return table|nil — mapping result with assignments, or nil
    function R.Orphan.check_ai_mapping(script_dir, orphans)
        local mapping_path = script_dir .. "mapping.json"
        local file, err = io.open(mapping_path, "r")
        if not file then return nil end

        local content = file:read("*a")
        file:close()

        local ok, mapping = pcall(R.JSON.parse, content)
        if not ok or not mapping then return nil end

        -- Remove the mapping file after reading
        os.remove(mapping_path)

        return mapping
    end
end
