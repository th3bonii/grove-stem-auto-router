-- Grove Stem Auto-Router / gui/main_window.lua
-- ReaImGui-based graphical interface
-- Usage: local gui = dofile(script_dir .. "gui/main_window.lua")
--        gui.launch(R)

local ImGui = reaper

local WINDOW_TITLE = "Grove Stem Auto-Router"

return {
    launch = function(R)
        local ctx = ImGui.ImGui_CreateContext(WINDOW_TITLE)

        -- ── persistent state across defer frames ──────────────────────────
        local state = {
            folder_path      = R._script_dir,
            stems            = {},
            stem_names       = {},
            stem_count       = 0,
            calibrated       = false,
            cal_count        = 0,
            overflow_mode    = "lanes",
            max_lanes        = 0,
            log_lines        = {},
            status           = "Ready",
            running          = false,
            scanned          = false,
            error_msg        = nil,
            available_tracks = {},  -- { track, name, guid }[]
            assignments      = {},  -- stem_idx -> { track, name }
            recent_guids     = {},  -- ordered GUIDs, most recent first
            last_content_h   = nil,  -- measured content height from previous frame
            orphan_data      = nil,  -- { orphans[], matched_count, orphan_count } from R.Orphan.collect()
            show_manifest    = false,  -- toggle for manifest table
            ai_provider      = "",  -- GUI-overridden AI provider (saved to ExtState)
            ai_model         = "",  -- GUI-overridden AI model
            ai_api_key       = "",  -- GUI-stored API key (saved to ExtState)
            ai_api_url       = "",  -- custom API base URL
        }

        local S = "GroveAutoRouter"  -- ExtState section

        -- ── persistent prefs ─────────────────────────────────────────────
        local function save_prefs()
            reaper.SetExtState(S, "folder_path",   state.folder_path,         true)
            reaper.SetExtState(S, "overflow_mode", state.overflow_mode,       true)
            reaper.SetExtState(S, "max_lanes",     tostring(state.max_lanes), true)
            reaper.SetExtState(S, "ai_provider",   state.ai_provider or "",   true)
            reaper.SetExtState(S, "ai_model",      state.ai_model or "",      true)
            reaper.SetExtState(S, "ai_api_key",    state.ai_api_key or "",    true)
            reaper.SetExtState(S, "ai_api_url",    state.ai_api_url or "",    true)
            if #state.recent_guids > 0 then
                reaper.SetExtState(S, "recent_guids",
                    table.concat(state.recent_guids, ","), true)
            else
                reaper.SetExtState(S, "recent_guids", "", true)
            end
        end

        local function load_prefs()
            local fp = reaper.GetExtState(S, "folder_path")
            if fp ~= "" then state.folder_path = fp end
            local om = reaper.GetExtState(S, "overflow_mode")
            if om ~= "" then state.overflow_mode = om end
            local ml = reaper.GetExtState(S, "max_lanes")
            if ml ~= "" then state.max_lanes = tonumber(ml) or 0 end
            local ap = reaper.GetExtState(S, "ai_provider")
            if ap ~= "" then state.ai_provider = ap end
            local am = reaper.GetExtState(S, "ai_model")
            if am ~= "" then state.ai_model = am end
            local ak = reaper.GetExtState(S, "ai_api_key")
            if ak ~= "" then state.ai_api_key = ak end
            local au = reaper.GetExtState(S, "ai_api_url")
            if au ~= "" then state.ai_api_url = au end
            local rg = reaper.GetExtState(S, "recent_guids")
            if rg ~= "" then
                for g in rg:gmatch("[^,]+") do
                    state.recent_guids[#state.recent_guids + 1] = g
                end
            end
        end

        -- ── helpers ──────────────────────────────────────────────────────
        local function log(msg)
            table.insert(state.log_lines, msg)
        end

        local function collect_tracks()
            local tracks = {}
            for i = 0, reaper.CountTracks(0) - 1 do
                local tr = reaper.GetTrack(0, i)
                local _, nm = reaper.GetTrackName(tr, "")
                tracks[#tracks + 1] = { track = tr, name = nm, guid = reaper.GetTrackGUID(tr) }
            end
            return tracks
        end

        local function run_matching(stems, tracks)
            local config = R.Config.load() or {}
            local guid_map = R.Calibration.get_track_map()  -- returns {guid→track} or nil
            local assignments = {}
            local matched_count = 0
            for idx, stem in ipairs(stems) do
                -- compute display name (first meaningful token) and store on stem
                local stem_tokens = R.MatchingEngine.tokenize and R.MatchingEngine.tokenize(stem.name)
                if stem_tokens and #stem_tokens > 0 then
                    stem.display_name = stem_tokens[1]
                else
                    stem.display_name = stem.name:gsub("%.[^%.]+$", "")
                end

                -- compute category for ALL stems (used by orphan collect and overflow dispatch)
                local category = nil
                if R.Import.normalize then
                    category = R.Import.normalize(stem.name, config)
                end
                if not category or category == "" then
                    category = "unknown"
                end

  local matched_track, matched_name, method =
    R.Import.match_stem(stem.name, tracks, config, guid_map)
  if matched_track then matched_count = matched_count + 1 end
  assignments[idx] = {
    track = matched_track,
    name = matched_name or "(no match)",
    method = method or "none",
    category = category,
    selected = false,        -- bulk-op checkbox state
    reason = "",             -- filled below from unmatched stems
  }
  if matched_track then
    assignments[idx].reason = ""
  else
    assignments[idx].reason = "no match"
  end
  end
    return assignments
end

local function scan_folder()
            state.error_msg = nil
            local config = R.Config.load() or {}
            local stems = R.Import.scan(state.folder_path)
            if #stems == 0 then
                state.error_msg = "No audio files found in that folder."
                state.stems = {}; state.stem_names = {}
                state.stem_count = 0; state.scanned = false
                log(state.error_msg)
                return
            end
            state.last_content_h = nil  -- force re-measure
            state.stems = stems
            state.stem_names = {}
            for _, s in ipairs(stems) do
                state.stem_names[#state.stem_names + 1] = s.name
            end
            state.stem_count = #stems
            state.available_tracks = collect_tracks()
            state.assignments = run_matching(stems, state.available_tracks)
  -- Collect orphan data for the orphans section
  state.orphan_data = R.Orphan.collect(stems, state.assignments)
  -- Sync bulk-selection state from assignments → orphan entries (scan→import gap)
  for _, o in ipairs(state.orphan_data.orphans) do
    local a = state.assignments[o.index]
    if a then o.selected = a.selected end
  end
  log("Matched: " .. state.orphan_data.matched_count .. ", Orphans: " .. state.orphan_data.orphan_count)

            -- Export orphans for AI proxy if AI is configured
            if state.orphan_data and state.orphan_data.orphan_count > 0 then
                R.Orphan.export_for_ai(state.orphan_data, state.available_tracks, R._script_dir, config)
                -- Override ai_config.json with GUI state values (persisted via ExtState)
                local ai_override = R.Config.get_ai_config() or {}
                if state.ai_provider ~= "" then ai_override.provider = state.ai_provider end
                if state.ai_model ~= "" then ai_override.model = state.ai_model end
                if state.ai_api_key ~= "" then ai_override.api_key = state.ai_api_key end
                local override_str = R.JSON.stringify(ai_override)
                local ov_file = io.open(R._script_dir .. "ai_config.json", "w")
                if ov_file then ov_file:write(override_str) ov_file:close() end
            end

            -- ── AI: call LLM directly via curl ────────────────────────────
            if state.orphan_data and state.orphan_data.orphan_count > 0
               and state.ai_api_key ~= "" then
                state.status = "AI: querying LLM..."
                local model = (state.ai_model ~= "" and state.ai_model) or "gpt-4o-mini"
                local provider = (state.ai_provider ~= "" and state.ai_provider) or "openai"
                log("AI: consulting " .. model .. " via " .. provider .. "...")

                -- Build prompts (shared by all providers)
                local orphan_names = {}
                for _, o in ipairs(state.orphan_data.orphans) do
                    orphan_names[#orphan_names + 1] = "  - " .. o.stem.name
                end
                local track_names = {}
                for _, t in ipairs(state.available_tracks) do
                    track_names[#track_names + 1] = "  - " .. t.name
                end

                local system_prompt = [[You are a music production assistant specializing in stem routing.
Given a list of orphan audio stems (files that couldn't be automatically matched)
and a list of available REAPER tracks, assign each stem to the most appropriate track.

Rules:
- Match based on MUSICAL FUNCTION, not just text similarity
- 808, sub, subby → any bass/sub track
- vox, vocal, voice, rap, hook → any vocal track
- synth, lead, pad, keys → any melody/keys track
- gtr, guitar → any guitar track
- fx, riser, sweep, impact, noise → any FX track
- strings, brass, horn → any orchestral track
- Drums/percussion elements → any drum track
- If unsure, put it in the closest matching category track
- NEVER create a new track name — only use available tracks

Respond with ONLY a JSON object: {"assignments": {"filename.wav": "Track Name", ...}}
No explanation, no markdown, no commentary.]]

                local user_prompt = "Assign these orphan stems to the most appropriate tracks.\n\nOrphan stems:\n"
                    .. table.concat(orphan_names, "\n")
                    .. "\n\nAvailable tracks:\n" .. table.concat(track_names, "\n")
                    .. "\n\nRespond with the JSON mapping."

                local base_url = state.ai_api_url
                if base_url == "" then
                    if provider == "gemini" then base_url = "https://generativelanguage.googleapis.com/v1beta"
                    elseif provider == "opencode" then base_url = "https://api.opencode.ai/v1"
                    else base_url = "https://api.openai.com/v1" end
                end

                local function shdq(s)
                    -- Escape string for use inside shell double-quoted context
                    return s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("%$", "\\$"):gsub("`", "\\`")
                end

                local req_str, curl_url, curl_auth_header, parse_response
                local is_gemini = provider == "gemini"

                if is_gemini then
                    -- ── Gemini native format ──────────────────────────────
                    local gemini_req = {
                        contents = {
                            {
                                role = "user",
                                parts = { { text = user_prompt } },
                            },
                        },
                        system_instruction = {
                            parts = { { text = system_prompt } },
                        },
                        generationConfig = {
                            response_mime_type = "application/json",
                            temperature = 0.1,
                        },
                    }
                    req_str = R.JSON.stringify(gemini_req)
                    curl_url = base_url .. "/models/" .. model .. ":generateContent"
                    curl_auth_header = ' -H "X-Goog-Api-Key: ' .. shdq(state.ai_api_key) .. '"'
                    parse_response = function(body)
                        local ok, resp = pcall(R.JSON.parse, body)
                        if not ok or not resp then return end
                        if resp.candidates and resp.candidates[1]
                           and resp.candidates[1].content
                           and resp.candidates[1].content.parts
                           and resp.candidates[1].content.parts[1] then
                            return resp.candidates[1].content.parts[1].text
                        end
                    end
                else
                    -- ── OpenAI-compatible format (openai, opencode, custom) ──
                    local oai_req = {
                        model = model,
                        messages = {
                            { role = "system", content = system_prompt },
                            { role = "user", content = user_prompt },
                        },
                        temperature = 0.1,
                        response_format = { type = "json_object" },
                    }
                    req_str = R.JSON.stringify(oai_req)
                    curl_url = base_url .. "/chat/completions"
                    curl_auth_header = ' -H "Authorization: Bearer ' .. shdq(state.ai_api_key) .. '"'
                    parse_response = function(body)
                        local ok, resp = pcall(R.JSON.parse, body)
                        if not ok or not resp then return end
                        if resp.choices and resp.choices[1] and resp.choices[1].message then
                            return resp.choices[1].message.content
                        elseif resp.error then
                            log("AI API error: " .. (resp.error.message or "unknown"))
                        end
                    end
                end

                -- Write request to temp file and call API via curl
                local tmp_path = R._script_dir .. "_ai_request.json"
                local tmp_f = io.open(tmp_path, "w")
                if tmp_f then
                    tmp_f:write(req_str)
                    tmp_f:close()

                    local curl_cmd = 'curl -s ' .. curl_url
                        .. ' -H "Content-Type: application/json"'
                        .. curl_auth_header
                        .. ' -d @' .. tmp_path

                    local ret, stdout = reaper.ExecProcess(curl_cmd, 30000)
                    os.remove(tmp_path)

                    if not ret then
                        log("AI: curl command failed — check network, API key, and URL")
                    elseif stdout and stdout ~= "" then
                        local content = parse_response(stdout)
                        if content and content ~= "" then
                            local ok2, mapping = pcall(R.JSON.parse, content)
                            if ok2 and mapping and mapping.assignments then
                                local mapping_str = R.JSON.stringify({
                                    assignments = mapping.assignments,
                                    status = "success",
                                })
                                local mf = io.open(R._script_dir .. "mapping.json", "w")
                                if mf then mf:write(mapping_str); mf:close() end
                                local count = 0
                                for _ in pairs(mapping.assignments) do count = count + 1 end
                                log("AI: " .. count .. " mapping(s) resolved")
                            else
                                log("AI: response wasn't valid JSON: " .. (content:sub(1, 120) or "empty"))
                            end
                        end
                    else
                        log("AI: API returned empty response (curl succeeded but no output)")
                    end
                end
            end

            state.scanned = true
            log("Found " .. #stems .. " stem(s) across " .. #state.available_tracks .. " track(s)")
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

            local config = R.Config.load()
            if not config then
                log("ERROR: config failed to load."); state.running = false
                state.status = "Error"; return
            end
            config.overflow_behavior = state.overflow_mode
            config.max_lanes_per_track = state.max_lanes

            -- Recompute orphan_data from current assignments (may have changed since scan)
            state.orphan_data = R.Orphan.collect(state.stems, state.assignments)

            if #state.stems == 0 then
                log("No stems to import."); state.running = false
                state.status = "Ready"; return
            end

            -- ── main pipeline ──────────────────────────────────────────
            reaper.PreventUIRefresh(1)
            reaper.Undo_BeginBlock()

            local ins, ovf, skip = 0, 0, 0

            -- Build resolved track name → list of tracks (for round-robin distribution)
            local trk_groups = {}
            for _, t in ipairs(state.available_tracks) do
                local tokens = R.MatchingEngine.tokenize(t.name)
                local resolved = R.MatchingEngine.resolve(tokens, config)
                table.sort(resolved)
                local key = table.concat(resolved, " ")
                if not trk_groups[key] then trk_groups[key] = {} end
                table.insert(trk_groups[key], t)
            end

            -- Group matched stems by their matched track's resolved name
            local stem_groups = {}
            for idx, stem in ipairs(state.stems) do
                local a = state.assignments[idx]
                if not a or not a.track then
                    skip = skip + 1
                else
                    local tokens = R.MatchingEngine.tokenize(a.name or "")
                    local resolved = R.MatchingEngine.resolve(tokens, config)
                    table.sort(resolved)
                    local key = table.concat(resolved, " ")
                    if not stem_groups[key] then stem_groups[key] = {} end
                    table.insert(stem_groups[key], {
                        stem = stem, cat = a.category or "unknown",
                    })
                end
            end

            -- Distribute round-robin across same-named tracks
            for key, stems in pairs(stem_groups) do
                local sib_tracks = trk_groups[key] or {}
                local nt = #sib_tracks
                if nt == 0 then
                    skip = skip + #stems
                else
                    local used = {}
                    for i, entry in ipairs(stems) do
                        local tr = sib_tracks[(i - 1) % nt + 1]
                        local guid = tostring(tr.track)
                        if not used[guid] then
                            R.Import.insert_media(entry.stem.path, tr.track, nil, config)
                            used[guid] = true; ins = ins + 1
                        else
                            R.Overflow.dispatch(entry.stem, tr.track, config, ovf, entry.cat)
                            ovf = ovf + 1
                        end
                    end
                end
            end

  -- After matched imports, create new tracks for selected no-match stems
  for idx, stem in ipairs(state.stems) do
    local a = state.assignments[idx]
    if a and a.selected and not a.track then
      local cfg2 = R.Config.load() or {}
  local orphan_entry = {
    stem = stem,
    category = a.category or "unknown",
    display = stem.display_name or stem.name,
    reason = a.reason or "no match",
  }
  local new_track = R.Orphan._create_track_from_orphan(orphan_entry, cfg2)
  if new_track then
    -- _create_track_from_orphan already inserts the media onto the new track
    ins = ins + 1
    a.track = new_track
    a.name = stem.name:gsub("%.[^%.]+$", "")
    a.selected = false
    a.reason = ""
  end
end
end
  end

  -- After import loop, try AI mapping for remaining orphans
  if state.orphan_data and state.orphan_data.orphan_count > 0
               and (state.ai_provider ~= "" or R.Config.get_ai_config().provider ~= "") then
                local mapping = R.Orphan.check_ai_mapping(R._script_dir, state.orphan_data)
                if mapping and mapping.assignments and next(mapping.assignments) then
                    -- Apply AI mappings
                    local ai_count = 0
                    for filename, track_name in pairs(mapping.assignments) do
                        -- Find the orphan stem by filename
                        local found_stem = false
                        local orphan_stem
                        for _, o in ipairs(state.orphan_data.orphans) do
                            if o.stem.name == filename then
                                found_stem = true
                                orphan_stem = o
                                break
                            end
                        end
                        if not found_stem then
                            log("AI: orphan stem '" .. filename .. "' not found — possibly already assigned")
                        else
                            -- Find the track by name
                            local found_track = false
                            for _, t in ipairs(state.available_tracks) do
                                if t.name:lower() == track_name:lower() then
                                    R.Import.insert_media(orphan_stem.stem.path, t.track, nil, config)
                                    ai_count = ai_count + 1
                                    ins = ins + 1
                                    found_track = true
                                    break
                                end
                            end
                            if not found_track then
                                log("AI: no track found for '" .. track_name .. "' (AI hallucinated name)")
                            end
                        end
                    end
                    if ai_count > 0 then
                        log("AI assigned " .. ai_count .. " orphan(s)")
                    end
                end
            end

            reaper.Undo_EndBlock(WINDOW_TITLE, 0)
            reaper.PreventUIRefresh(-1)

        local orphan_count = state.orphan_data and state.orphan_data.orphan_count or 0
        local msg = ins .. " inserted, " .. ovf .. " overflowed, " .. skip .. " skipped"
            .. (orphan_count > 0
                and (", " .. orphan_count .. " orphan(s) — use auto-insert or manual reassign")
                or "")
            log(msg); state.status = msg
            state.running = false
        end

        -- ── min width: import button (300px) + padding ─
        local min_w = 316  -- fallback
        local pad_y = 8    -- fallback bottom margin
        local ok_wp, pad_x, tmp_pad_y = pcall(ImGui.ImGui_GetStyleVar, ctx, ImGui.ImGui_StyleVar_WindowPadding())
        if ok_wp and pad_x then
            min_w = 300 + 2 * pad_x
            pad_y = tmp_pad_y or pad_x
        end

        -- ── defer render loop ──────────────────────────────────────────
        local function loop()
            local show_sidebar = (state.sidebar_visible ~= false) and (state.show_manifest or (state.scanned and #state.stems > 0))
            -- widen minimum when sidebar is active
            local eff_min_w = min_w
            if show_sidebar then
                eff_min_w = math.max(eff_min_w, min_w + 324 + 4)
            end
            -- fully locked to measured content — no resize, auto-adapts to state
            local min_h, max_h, max_w
            if state.last_content_h then
                -- measurement from previous frame is accurate → lock
                min_h = state.last_content_h
                max_h = min_h
                max_w = eff_min_w
            else
                -- first frame after state change: free resize to stabilize
                min_h = state.scanned and 590 or 395
                max_h = 9999
                max_w = 9999
            end
            ImGui.ImGui_SetNextWindowSizeConstraints(ctx, eff_min_w, min_h, max_w, max_h)
            local main_flags = ImGui.ImGui_WindowFlags_NoCollapse() | ImGui.ImGui_WindowFlags_NoScrollbar()
            local visible, open = ImGui.ImGui_Begin(
                ctx, WINDOW_TITLE, true,
                main_flags
            )

            if visible then
                ImGui.ImGui_PushStyleVar(ctx, ImGui.ImGui_StyleVar_FrameRounding(), 6)
                ImGui.ImGui_PushStyleVar(ctx, ImGui.ImGui_StyleVar_ScrollbarSize(), 6)

                -- Measure actual window chrome (title + borders + padding) for precise height
                local chrome_h = pad_y + 22  -- fallback estimate
                local ok_ws, win_h = pcall(ImGui.ImGui_GetWindowSize, ctx)
                if ok_ws and win_h then
                    local ok_cmin, cmin_y = pcall(ImGui.ImGui_GetWindowContentRegionMin, ctx)
                    local ok_cmax, cmax_y = pcall(ImGui.ImGui_GetWindowContentRegionMax, ctx)
                    if ok_cmin and ok_cmax and cmin_y and cmax_y then
                        chrome_h = win_h - (cmax_y - cmin_y)
                    end
                end
                if chrome_h < pad_y + 10 then chrome_h = pad_y + 10 end

                if show_sidebar then
                    local main_w, _ = ImGui.ImGui_GetContentRegionAvail(ctx)
                    local sidebar_w = 324
                    ImGui.ImGui_BeginChild(ctx, "##main_col", math.max(300, main_w - sidebar_w - 4), 0, 0)
                end

                -- ════════════════════════════════════════════════════════
                --  FOLDER + CALIBRATION inline
                -- ════════════════════════════════════════════════════════
                ImGui.ImGui_Separator(ctx)
                ImGui.ImGui_AlignTextToFramePadding(ctx); ImGui.ImGui_Text(ctx, "STEMS FOLDER")
                ImGui.ImGui_SameLine(ctx, 0, 5)
                if ImGui.ImGui_Button(ctx, "Browse...", 48) then
                    local ret, path = reaper.GetUserFileNameForRead(
                        "", "Select ONE stem from your export folder",
                        "*.wav;*.flac;*.mp3"
                    )
                    if ret then
                        local dir = path:gsub("\\", "/"):match("^(.*/)")
                        if dir then
                            state.last_content_h = nil  -- force re-measure
                            state.folder_path = dir
                            state.scanned = false; state.error_msg = nil
                            log("Folder: " .. dir)
                            save_prefs()
                        end
                    end
                end
                ImGui.ImGui_SameLine(ctx, 0, 5)
                if ImGui.ImGui_Button(ctx, "Calibrate", 53) then
                    do_calibrate()
                end
                ImGui.ImGui_SameLine(ctx, 0, 5)
                if ImGui.ImGui_Button(ctx, "Scan Folder", 67) then
                    scan_folder()
                end
                ImGui.ImGui_SameLine(ctx, 0, 10)
                if ImGui.ImGui_Button(ctx, show_sidebar and "◀" or "▶", 22) then
                    state.sidebar_visible = not state.sidebar_visible
                    state.last_content_h = nil
                end
                ImGui.ImGui_SetNextItemWidth(ctx, -1)
                local _, _ = ImGui.ImGui_InputText(ctx, "##path", state.folder_path, ImGui.ImGui_InputTextFlags_ReadOnly())

                if state.error_msg then
                    ImGui.ImGui_Text(ctx, state.error_msg)
                end

                -- overflow controls inline with the button bar
                if ImGui.ImGui_RadioButton(ctx, "New Track",
                                            state.overflow_mode == "new_track") then
                    state.overflow_mode = "new_track"
                    save_prefs()
                end
                ImGui.ImGui_SameLine(ctx, 0, 5)
                if ImGui.ImGui_RadioButton(ctx, "Lanes",
                                            state.overflow_mode == "lanes") then
                    state.overflow_mode = "lanes"
                    save_prefs()
                end
                ImGui.ImGui_SameLine(ctx, 0, 8)
                ImGui.ImGui_Text(ctx, "Max:")
                ImGui.ImGui_SameLine(ctx, 0, 2)
                ImGui.ImGui_SetNextItemWidth(ctx, 90)
                local ch, v = ImGui.ImGui_InputInt(ctx, "##ml", state.max_lanes, 1, 5)
                if ch then state.max_lanes = math.max(0, v); save_prefs() end

                -- calibration status
                ImGui.ImGui_Separator(ctx)
                if state.calibrated then
                    ImGui.ImGui_Text(ctx, "Calibrated: " .. state.cal_count .. " track(s)")
                else
                    ImGui.ImGui_Text(ctx, "No calibration data")
                end
ImGui.ImGui_SameLine(ctx)
if ImGui.ImGui_Button(ctx, "Show Manifest", 90) then
    state.show_manifest = not state.show_manifest
    if state.show_manifest then state.sidebar_visible = true end
    state.last_content_h = nil  -- allow resize for sidebar
end
ImGui.ImGui_Spacing(ctx)

                -- ════════════════════════════════════════════════════════
                --  AI SETTINGS
                -- ════════════════════════════════════════════════════════
                ImGui.ImGui_Separator(ctx)
                ImGui.ImGui_Text(ctx, "AI ASSISTANT")
                ImGui.ImGui_Text(ctx, "Resolves orphan stems via LLM (curl — no extra deps)")

                -- Default API URLs per provider
                local function default_api_url(provider)
                    if provider == "gemini" then return "https://generativelanguage.googleapis.com/v1beta"
                    elseif provider == "opencode" then return "https://api.opencode.ai/v1"
                    else return "https://api.openai.com/v1" end
                end

                local ai_cfg = R.Config.get_ai_config()
                if ai_cfg then
                    -- Resolve current values (state override → config default → hardcoded default)
                    local cur_provider = (state.ai_provider ~= "" and state.ai_provider) or ai_cfg.provider or "openai"
                    local cur_model    = (state.ai_model ~= "" and state.ai_model) or ai_cfg.model or "gpt-4o-mini"
                    local cur_url      = state.ai_api_url
                    if cur_url == "" then cur_url = default_api_url(cur_provider) end

                    -- Provider dropdown
                    ImGui.ImGui_SetNextItemWidth(ctx, -80)
                    if ImGui.ImGui_BeginCombo(ctx, "##provider", cur_provider) then
                        local providers = {"openai", "opencode", "gemini"}
                        for i, p in ipairs(providers) do
                            local sel = p == cur_provider
                            if ImGui.ImGui_Selectable(ctx, p, sel) then
                                state.ai_provider = p
                                state.ai_model = ""
                                -- Auto-fill URL when switching provider
                                state.ai_api_url = default_api_url(p)
                                save_prefs()
                            end
                            if sel then ImGui.ImGui_SetItemDefaultFocus(ctx) end
                        end
                        ImGui.ImGui_EndCombo(ctx)
                    end
                    ImGui.ImGui_SameLine(ctx, 0, 4)
                    ImGui.ImGui_SetNextItemWidth(ctx, -1)
                    local ch_m, new_model = ImGui.ImGui_InputText(ctx, "##model", cur_model)
                    if ch_m then state.ai_model = new_model; save_prefs() end

                    -- API Key (masked)
                    local masked = string.rep("*", #state.ai_api_key)
                    local display_key = state.ai_api_key ~= "" and masked or ""
                    ImGui.ImGui_Text(ctx, "API Key:")
                    ImGui.ImGui_SameLine(ctx, 0, 4)
                    ImGui.ImGui_SetNextItemWidth(ctx, -1)
                    local ch_k, new_key = ImGui.ImGui_InputText(ctx, "##api_key", display_key,
                        ImGui.ImGui_InputTextFlags_Password())
                    if ch_k then
                        state.ai_api_key = new_key
                        save_prefs()
                    end

                    -- API URL (editable, with provider-appropriate default)
                    ImGui.ImGui_Text(ctx, "API URL:")
                    ImGui.ImGui_SameLine(ctx, 0, 4)
                    ImGui.ImGui_SetNextItemWidth(ctx, -1)
                    local ch_u, new_url = ImGui.ImGui_InputText(ctx, "##api_url", cur_url)
                    if ch_u then state.ai_api_url = new_url; save_prefs() end

                    ImGui.ImGui_Text(ctx, "Auto-runs on Scan — requires curl (built-in)")
                end

                ImGui.ImGui_Spacing(ctx)

                -- ════════════════════════════════════════════════════════
                --  IMPORT BUTTON
                -- ════════════════════════════════════════════════════════
                local ok = state.scanned and state.stem_count > 0
                           and not state.running
                if ok then
                    if ImGui.ImGui_Button(ctx, "IMPORT STEMS", -1, 40) then
                        do_import()
                    end
                else
                    ImGui.ImGui_Text(ctx, "[Scan a folder to enable import]")
                end
                ImGui.ImGui_Text(ctx, state.status)

                ImGui.ImGui_Spacing(ctx)

                -- ════════════════════════════════════════════════════════
                --  LOG
                -- ════════════════════════════════════════════════════════
                ImGui.ImGui_Separator(ctx); ImGui.ImGui_Text(ctx, "LOG")
                local log_text = table.concat(state.log_lines, "\n")
                if #log_text > 0 then log_text = log_text .. "\n" end
                ImGui.ImGui_SetNextItemWidth(ctx, -1)
                local ch, newtxt = ImGui.ImGui_InputTextMultiline(ctx, "##log", log_text, 0, 120, ImGui.ImGui_InputTextFlags_ReadOnly())

                -- measure main content height before sidebar
                local main_h = ImGui.ImGui_GetCursorPosY(ctx)

                if show_sidebar then
                    ImGui.ImGui_EndChild(ctx)  -- close ##main_col
                    ImGui.ImGui_SameLine(ctx)
                    -- sidebar height = main content height, so bottom border aligns with log
                    local sb_open = ImGui.ImGui_BeginChild(ctx, "##sidebar", 324, main_h, 0, ImGui.ImGui_WindowFlags_NoScrollbar())
                    if sb_open then
                    local sb_full_h = main_h  -- available height is the constrained child height
                    ImGui.ImGui_Separator(ctx)

                    -- MANIFEST
                    if state.show_manifest then
                        local man_h = math.max(60, math.floor(sb_full_h / 2) - 28)
                        ImGui.ImGui_Text(ctx, "TEMPLATE MANIFEST")
                        local tracks = collect_tracks()
                        local guid_map = R.Calibration.get_track_map()
                        if ImGui.ImGui_BeginChild(ctx, "##manifest", 0, man_h, ImGui.ImGui_ChildFlags_Borders()) then
                            ImGui.ImGui_Text(ctx, "Name / GUID / Cal")
                            ImGui.ImGui_Separator(ctx)
                            for idx, t in ipairs(tracks) do
                                local depth = reaper.GetMediaTrackInfo_Value(t.track, "I_FOLDERDEPTH")
                                local cal_status = "No"
                                if guid_map then
                                    local ok_guid, guid = pcall(reaper.GetTrackGUID, t.track)
                                    if ok_guid and guid and guid_map[guid] then
                                        cal_status = "YES"
                                    end
                                end
                                local guid_short = (t.guid or ""):sub(1, 12) .. ".."
                                ImGui.ImGui_Text(ctx, idx .. ". " .. t.name)
                                ImGui.ImGui_SameLine(ctx)
                                ImGui.ImGui_TextDisabled(ctx, guid_short .. " d" .. depth .. " " .. cal_status)
                            end
                        end
                        ImGui.ImGui_EndChild(ctx)
                    end

                    -- STEMS (bottom half)
                    if state.scanned and #state.stems > 0 then
                        ImGui.ImGui_Separator(ctx)
                        ImGui.ImGui_Text(ctx, "STEMS (" .. state.stem_count .. ") — click track to reassign")
                        local to_delete = {}

                        -- Sticky header (does not scroll with stems)
                        local cb_col_w = 24
                        local max_stem_w = 0
                        for _, s in ipairs(state.stems) do
                            local w, _ = ImGui.ImGui_CalcTextSize(ctx, s.name)
                            if w > max_stem_w then max_stem_w = w end
                        end
                        local sb_cw = select(1, ImGui.ImGui_GetContentRegionAvail(ctx))
                        local arrow_x = math.min(cb_col_w + max_stem_w + 8, math.floor(sb_cw * 0.65))

                        local all_selected = true
                        for _, a in ipairs(state.assignments) do
                            if not a.selected then all_selected = false; break end
                        end
                        local hdr_ch, hdr_val = ImGui.ImGui_Checkbox(ctx, "##selall", all_selected)
                        if hdr_ch then
                            for idx = 1, #state.assignments do
                                state.assignments[idx].selected = hdr_val
                            end
                        end
                        ImGui.ImGui_SameLine(ctx, cb_col_w, 4)
                        ImGui.ImGui_Text(ctx, "(all stems)")
                        ImGui.ImGui_SameLine(ctx, 0, 8)
                        if ImGui.ImGui_Button(ctx, "Del Sel", 50) then
                            local marked = {}
                            for i = 1, #state.assignments do
                                if state.assignments[i].selected then marked[#marked + 1] = i end
                            end
                            for _, i in ipairs(marked) do to_delete[#to_delete + 1] = i end
                        end
                        ImGui.ImGui_SameLine(ctx, 0, 4)
                        if ImGui.ImGui_Button(ctx, "Create Sel", 57) then
                            local cfg = R.Config.load() or {}
                            local n = 0
                            for idx, stem in ipairs(state.stems) do
                                local a = state.assignments[idx]
                                if a and a.selected and not a.track then
                                    local o = {stem=stem, category=a.category or "unknown",
                                               display=stem.display_name or stem.name, reason=a.reason or "no match"}
                                    R.Orphan._create_track_from_orphan(o, cfg); n = n + 1
                                end
                            end
                            if n > 0 then
                                log("Created " .. n .. " new track(s) from selected stems.")
                                state.orphan_data = R.Orphan.collect(state.stems, state.assignments)
                                for _, o in ipairs(state.orphan_data.orphans) do
                                    local aa = state.assignments[o.index]
                                    if aa then o.selected = aa.selected end
                                end
                            else log("No stems selected — check the box next to a stem first.") end
                        end
                        ImGui.ImGui_SameLine(ctx, 0, 4)
                        if ImGui.ImGui_Button(ctx, "New trk", 44) then
                            reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
                        end
                        ImGui.ImGui_SameLine(ctx, 0, 4)
                        if ImGui.ImGui_Button(ctx, "Resolve AI", 0) then
                            if state.ai_api_key == "" then
                                log("AI: set an API key first (see AI ASSISTANT section).")
                            else scan_folder() end
                        end
                        ImGui.ImGui_Separator(ctx)

                        local stems_avail = select(2, ImGui.ImGui_GetContentRegionAvail(ctx))
                        local stems_h = math.max(60, stems_avail - 4)
                        local sv = ImGui.ImGui_BeginChild(ctx, "##stems", 0, stems_h, 0)
                        if sv then
                            -- orphan count at TOP
                            local orphan_count = 0
                            for _, a in ipairs(state.assignments) do
                                if not a.track then orphan_count = orphan_count + 1 end
                            end
                            if orphan_count > 0 then
                                ImGui.ImGui_Text(ctx, "ORPHANS (" .. orphan_count .. ") — no track match")
                            end
                            for idx, stem in ipairs(state.stems) do
                                local a = state.assignments[idx]
                                local track_name = a and a.name or "(no match)"
                                local is_orphan = not (a and a.track)
                                ImGui.ImGui_PushID(ctx, idx)
                                ImGui.ImGui_BeginGroup(ctx)
                                local checked = a and a.selected or false
                                local ch, val = ImGui.ImGui_Checkbox(ctx, "##cb" .. idx, checked)
                                if ch and a then a.selected = val end
                                ImGui.ImGui_SameLine(ctx, cb_col_w, 4)
                                -- truncate long names so they don't overlap the arrow/combo
                                local name_avail = math.max(20, arrow_x - cb_col_w - 10)
                                local nw, _ = ImGui.ImGui_CalcTextSize(ctx, stem.name)
                                local display_name = stem.name
                                if nw > name_avail then
                                    for i = #stem.name - 1, 3, -1 do
                                        local sub = stem.name:sub(1, i) .. ".."
                                        local tw, _ = ImGui.ImGui_CalcTextSize(ctx, sub)
                                        if tw <= name_avail then
                                            display_name = sub
                                            break
                                        end
                                    end
                                end
                                ImGui.ImGui_Text(ctx, display_name)
                                if display_name ~= stem.name then
                                    if ImGui.ImGui_IsItemHovered(ctx) then
                                        ImGui.ImGui_SetTooltip(ctx, stem.name)
                                    end
                                end
                                ImGui.ImGui_SameLine(ctx, arrow_x, 2)
                                ImGui.ImGui_Text(ctx, "→")
                                ImGui.ImGui_SameLine(ctx, 0, 2)
                                ImGui.ImGui_SetNextItemWidth(ctx, -1)
                                if ImGui.ImGui_BeginCombo(ctx, "##track", track_name) then
                                    local recents = {}
                                    for ri = 1, math.min(5, #state.recent_guids) do
                                        recents[state.recent_guids[ri]] = ri
                                    end
                                    local recent_list, rest = {}, {}
                                    for _, t in ipairs(state.available_tracks) do
                                        if recents[t.guid] then
                                            recent_list[#recent_list + 1] = t
                                        else
                                            rest[#rest + 1] = t
                                        end
                                    end
                                    table.sort(recent_list, function(a, b)
                                        return (recents[a.guid] or 99) < (recents[b.guid] or 99)
                                    end)
                                    local has_recent = #recent_list > 0
                                    local has_rest = #rest > 0
                                    for _, t in ipairs(recent_list) do
                                        local sel = a and a.track == t.track or false
                                        if ImGui.ImGui_Selectable(ctx, t.name, sel) then
                                            local existing = state.assignments[idx]
                                            state.assignments[idx] = {
                                                track = t.track,
                                                name = t.name,
                                                category = (existing and existing.category) or "unknown",
                                                selected = (existing and existing.selected) or false,
                                                reason = "",
                                                method = "manual",
                                            }
                                            local guid = t.guid
                                            for ri = #state.recent_guids, 1, -1 do
                                                if state.recent_guids[ri] == guid then
                                                    table.remove(state.recent_guids, ri)
                                                end
                                            end
                                            table.insert(state.recent_guids, 1, guid)
                                            if #state.recent_guids > 20 then
                                                table.remove(state.recent_guids)
                                            end
                                            save_prefs()
                                        end
                                    end
                                    if has_recent and has_rest then
                                        ImGui.ImGui_Separator(ctx)
                                    end
                                    for _, t in ipairs(rest) do
                                        local sel = a and a.track == t.track or false
                                        if ImGui.ImGui_Selectable(ctx, t.name, sel) then
                                            local existing = state.assignments[idx]
                                            state.assignments[idx] = {
                                                track = t.track,
                                                name = t.name,
                                                category = (existing and existing.category) or "unknown",
                                                selected = (existing and existing.selected) or false,
                                                reason = "",
                                                method = "manual",
                                            }
                                            local guid = t.guid
                                            for ri = #state.recent_guids, 1, -1 do
                                                if state.recent_guids[ri] == guid then
                                                    table.remove(state.recent_guids, ri)
                                                end
                                            end
                                            table.insert(state.recent_guids, 1, guid)
                                            if #state.recent_guids > 20 then
                                                table.remove(state.recent_guids)
                                            end
                                            save_prefs()
                                        end
                                    end
                                    ImGui.ImGui_EndCombo(ctx)
                                end
                                ImGui.ImGui_EndGroup(ctx)
                                -- right-click on row opens context menu
                                if ImGui.ImGui_IsMouseClicked(ctx, 1) and ImGui.ImGui_IsItemHovered(ctx) then
                                    ImGui.ImGui_OpenPopup(ctx, "##stem_ctx" .. idx)
                                end
                                if ImGui.ImGui_BeginPopup(ctx, "##stem_ctx" .. idx) then
                                    if ImGui.ImGui_MenuItem(ctx, "Del") then
                                        to_delete[#to_delete + 1] = idx
                                    end
                                    ImGui.ImGui_EndPopup(ctx)
                                end
                                ImGui.ImGui_PopID(ctx)
                            end
                            -- to_delete processing
                            if #to_delete > 0 then
                                table.sort(to_delete, function(a, b) return a > b end)
                                for _, idx in ipairs(to_delete) do
                                    table.remove(state.stems, idx)
                                    table.remove(state.stem_names, idx)
                                    table.remove(state.assignments, idx)
                                    state.stem_count = #state.stems
                                end
                                state.available_tracks = collect_tracks()
                                state.orphan_data = R.Orphan.collect(state.stems, state.assignments)
                                for _, o in ipairs(state.orphan_data.orphans) do
                                    local aa = state.assignments[o.index]
                                    if aa then o.selected = aa.selected end
                                end
                                log("Removed " .. #to_delete .. " stem(s).")
                            end
                        end
                        ImGui.ImGui_EndChild(ctx)
                    end

                    if sb_open then
                        ImGui.ImGui_EndChild(ctx)
                    end
                    end  -- closes if sb_open (sidebar BeginChild guard)
                    state.cached_main_h = main_h
                    state.last_content_h = main_h + chrome_h
                else
                    -- Use cached main_h from when sidebar was deployed for consistent height
                    local no_sb_h = state.cached_main_h or main_h
                    state.last_content_h = no_sb_h + chrome_h
                end

                ImGui.ImGui_PopStyleVar(ctx)
                ImGui.ImGui_PopStyleVar(ctx)
                ImGui.ImGui_End(ctx)
            end

            if open then
                reaper.defer(loop)
            else
                save_prefs()
                if ImGui.ImGui_DestroyContext then ImGui.ImGui_DestroyContext(ctx) end
            end
        end

        -- ── bootstrap ────────────────────────────────────────────────────
        -- ── measure what the initial content needs ──
        local est_h = 395  -- basic UI fits this (no stems yet)
        ImGui.ImGui_SetNextWindowSize(ctx, min_w, est_h,
                                      ImGui.ImGui_Cond_Always())
        load_prefs()

        -- greet + cleanup stale orphan/AI files from previous runs
        pcall(os.remove, R._script_dir .. "orphans.json")
        pcall(os.remove, R._script_dir .. "_ai_request.json")
        local stale_map = io.open(R._script_dir .. "mapping.json", "r")
        if stale_map then stale_map:close(); pcall(os.remove, R._script_dir .. "mapping.json") end

        local cfg = R.Config.load()
        if cfg then
            state.overflow_mode = cfg.overflow_behavior or "lanes"
            state.max_lanes = 0
        end
        local cc = R.Calibration.get_count()
        if cc > 0 then state.calibrated = true; state.cal_count = cc end

        log(WINDOW_TITLE .. " v2")
        log("Calibration: " .. cc .. " track(s)")
        log("Config: " .. (cfg and "loaded" or "defaults"))
        log("Ready. Browse to your stem folder and click Scan.")

        loop()
    end
}
