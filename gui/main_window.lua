-- Grove Stem Auto-Router / gui/main_window.lua
-- ReaImGui-based graphical interface
-- Usage: local gui = dofile(script_dir .. "gui/main_window.lua")
--        gui.launch(R)

local ImGui = reaper

return {
    launch = function(R)
        local ctx = ImGui.ImGui_CreateContext("Grove Stem Auto-Router")

        -- ── persistent state across defer frames ──────────────────────────
        local state = {
            folder_path   = R._script_dir,
            stems         = {},
            stem_names    = {},
            stem_count    = 0,
            calibrated    = false,
            cal_count     = 0,
            overflow_mode = "lanes",
            max_lanes     = 6,
            log_lines     = {},
            status        = "Ready",
            running       = false,
            scanned       = false,
            error_msg     = nil,
        }

        -- ── helpers ──────────────────────────────────────────────────────
        local function log(msg)
            table.insert(state.log_lines, msg)
        end

        local function scan_folder()
            state.error_msg = nil
            local stems = R.Import.scan(state.folder_path)
            if #stems == 0 then
                state.error_msg = "No audio files found in that folder."
                state.stems = {}; state.stem_names = {}
                state.stem_count = 0; state.scanned = false
                log(state.error_msg)
                return
            end
            state.stems = stems
            state.stem_names = {}
            for _, s in ipairs(stems) do
                state.stem_names[#state.stem_names + 1] = s.name
            end
            state.stem_count = #stems
            state.scanned = true
            log("Found " .. #stems .. " stem(s)")
        end

        local function do_calibrate()
            ImGui.ShowMessageBox("Select the tracks to calibrate, then click OK.",
                                 "Grove Calibration", 0)
            local sel = {}
            for i = 0, reaper.CountSelectedTracks(0) - 1 do
                sel[#sel + 1] = reaper.GetSelectedTrack(0, i)
            end
            if #sel == 0 then
                log("Calibration cancelled — no tracks selected.")
                return
            end
            local n = R.Calibration.save(sel)
            if n and n > 0 then
                state.calibrated = true; state.cal_count = n
                log("Calibration saved: " .. n .. " track(s).")
            end
        end

        local function do_import()
            if state.running then return end
            state.running = true
            state.status = "Importing..."

            -- read config (with GUI overrides)
            local config = R.Config.load()
            if not config then
                log("ERROR: config failed to load."); state.running = false
                state.status = "Error"; return
            end
            -- apply GUI-side overrides for this run
            config.overflow_behavior = state.overflow_mode
            config.max_lanes_per_track = state.max_lanes

            -- calibration (optional)
            local guid_map
            local raw = R.Calibration.load()
            if raw then
                local valid, stale = R.Calibration.validate(raw)
                if next(valid) then guid_map = valid end
            end

            -- collect REAPER tracks
            local rpp_tracks = {}
            for i = 0, reaper.CountTracks(0) - 1 do
                local tr = reaper.GetTrack(0, i)
                local _, nm = reaper.GetTrackName(tr, "")
                rpp_tracks[#rpp_tracks + 1] = { track = tr, name = nm }
            end

            if #state.stems == 0 then
                log("No stems to import."); state.running = false
                state.status = "Ready"; return
            end

            -- ── main pipeline ──────────────────────────────────────────
            reaper.PreventUIRefresh(1)
            reaper.Undo_BeginBlock()

            local used, ins, ovf, skip = {}, 0, 0, 0
            for _, stem in ipairs(state.stems) do
                local cat = R.Import.normalize(stem.name, config)
                local matched, _ = R.Import.match(cat, rpp_tracks, guid_map)
                if matched then
                    local k = tostring(matched)
                    if not used[k] then
                        R.Import.insert_media(stem.path, matched)
                        used[k] = true; ins = ins + 1
                    else
                        R.Overflow.dispatch(stem, matched, config, ovf)
                        ovf = ovf + 1
                    end
                else
                    skip = skip + 1
                end
            end

            reaper.Undo_EndBlock("Grove Stem Auto-Router", -1)
            reaper.PreventUIRefresh(-1)

            local msg = ins .. " inserted, " .. ovf .. " overflowed, " .. skip .. " skipped."
            log(msg); state.status = msg
            state.running = false
        end

        -- ── defer render loop ──────────────────────────────────────────
        local function loop()
            local visible, open = ImGui.ImGui_Begin(
                ctx, "Grove Stem Auto-Router", true,
                ImGui.ImGui_WindowFlags_NoCollapse()
            )

            if visible then

                -- ════════════════════════════════════════════════════════
                --  FOLDER
                -- ════════════════════════════════════════════════════════
                ImGui.ImGui_Separator(ctx); ImGui.ImGui_Text(ctx, "STEMS FOLDER")
                ImGui.ImGui_SameLine(ctx)
                if ImGui.ImGui_Button(ctx, "Browse...") then
                    local ret, path = reaper.GetUserFileNameForRead(
                        "", "Select ONE stem from your export folder",
                        "*.wav;*.flac;*.mp3"
                    )
                    if ret then
                        local dir = path:gsub("\\", "/"):match("^(.*/)")
                        if dir then
                            state.folder_path = dir
                            state.scanned = false; state.error_msg = nil
                            log("Folder: " .. dir)
                        end
                    end
                end
                ImGui.ImGui_Text(ctx, state.folder_path)

                if ImGui.ImGui_Button(ctx, "Scan Folder") then
                    scan_folder()
                end

                if state.error_msg then
                    ImGui.ImGui_Text(ctx, state.error_msg)
                end

                ImGui.ImGui_Spacing(ctx)

                -- ════════════════════════════════════════════════════════
                --  CALIBRATION
                -- ════════════════════════════════════════════════════════
                ImGui.ImGui_Separator(ctx); ImGui.ImGui_Text(ctx, "CALIBRATION")
                ImGui.ImGui_SameLine(ctx)
                if ImGui.ImGui_Button(ctx, "Calibrate Tracks") then
                    do_calibrate()
                end
                if state.calibrated then
                    ImGui.ImGui_Text(ctx, "Calibrated: " .. state.cal_count .. " track(s)")
                else
                    ImGui.ImGui_Text(ctx, "No calibration data")
                end

                ImGui.ImGui_Spacing(ctx)

                -- ════════════════════════════════════════════════════════
                --  OVERFLOW SETTINGS
                -- ════════════════════════════════════════════════════════
                ImGui.ImGui_Separator(ctx); ImGui.ImGui_Text(ctx, "OVERFLOW")
                if ImGui.ImGui_RadioButton(ctx, "New Track",
                                           state.overflow_mode == "new_track") then
                    state.overflow_mode = "new_track"
                end
                ImGui.ImGui_SameLine(ctx)
                if ImGui.ImGui_RadioButton(ctx, "Lanes",
                                           state.overflow_mode == "lanes") then
                    state.overflow_mode = "lanes"
                end
                ImGui.ImGui_SameLine(ctx)
                ImGui.ImGui_Text(ctx, "   Max lanes:")
                ImGui.ImGui_SameLine(ctx)
                local ch, v = ImGui.ImGui_InputInt(ctx, "##ml", state.max_lanes, 1, 5)
                if ch then state.max_lanes = math.max(0, v) end

                ImGui.ImGui_Spacing(ctx)

                -- ════════════════════════════════════════════════════════
                --  STEM LIST
                -- ════════════════════════════════════════════════════════
                if state.scanned then
                    ImGui.ImGui_Separator(ctx)
                    ImGui.ImGui_Text(ctx, "STEMS (" .. state.stem_count .. ")")
                    if ImGui.ImGui_BeginChild(ctx, "##stems", {0, 140}, true) then
                        for _, nm in ipairs(state.stem_names) do
                            ImGui.ImGui_BulletText(ctx, nm)
                        end
                    end
                    ImGui.ImGui_EndChild(ctx)
                end

                ImGui.ImGui_Spacing(ctx)

                -- ════════════════════════════════════════════════════════
                --  IMPORT BUTTON
                -- ════════════════════════════════════════════════════════
                local ok = state.scanned and state.stem_count > 0
                           and not state.running
                if ok then
                    if ImGui.ImGui_Button(ctx, "IMPORT STEMS", 300, 40) then
                        do_import()
                    end
                else
                    ImGui.ImGui_Text(ctx, "[Scan a folder to enable import]")
                end
                ImGui.ImGui_SameLine(ctx)
                ImGui.ImGui_Text(ctx, state.status)

                ImGui.ImGui_Spacing(ctx)

                -- ════════════════════════════════════════════════════════
                --  LOG
                -- ════════════════════════════════════════════════════════
                ImGui.ImGui_Separator(ctx); ImGui.ImGui_Text(ctx, "LOG")
                if ImGui.ImGui_BeginChild(ctx, "##log", {0, 120}, true) then
                    for _, line in ipairs(state.log_lines) do
                        ImGui.ImGui_TextWrapped(ctx, line)
                    end
                    -- auto-scroll to bottom
                    ImGui.ImGui_SetScrollHereY(ctx, 1)
                end
                ImGui.ImGui_EndChild(ctx)

                ImGui.ImGui_End(ctx)
            end

            if open then
                reaper.defer(loop)
            else
                ImGui.ImGui_DestroyContext(ctx)
            end
        end

        -- ── bootstrap ────────────────────────────────────────────────────
        ImGui.ImGui_SetNextWindowSize(ctx, 620, 540,
                                      ImGui.ImGui_Cond_FirstUseEver())

        -- greet
        local cfg = R.Config.load()
        if cfg then
            state.overflow_mode = cfg.overflow_behavior or "lanes"
            state.max_lanes = cfg.max_lanes_per_track or 6
        end
        local cc = R.Calibration.get_count()
        if cc > 0 then state.calibrated = true; state.cal_count = cc end

        log("Grove Stem Auto-Router v2")
        log("Calibration: " .. cc .. " track(s)")
        log("Config: " .. (cfg and "loaded" or "defaults"))
        log("Ready. Browse to your stem folder and click Scan.")

        loop()
    end
}
