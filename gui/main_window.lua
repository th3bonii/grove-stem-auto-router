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
            cached_window_h_sidebar = nil,  -- height when sidebar visible
            cached_window_h_noside  = nil,  -- height when sidebar hidden
            sidebar_visible       = true,  -- sidebar toggle state (persisted)
            orphan_data      = nil,  -- { orphans[], matched_count, orphan_count } from R.Orphan.collect()
            show_manifest    = false,  -- toggle for manifest table
            show_heatmap     = false,  -- toggle for heatmap view
            ai_provider      = "",  -- GUI-overridden AI provider (saved to ExtState)
            ai_model         = "",  -- GUI-overridden AI model
            ai_api_key       = "",  -- GUI-stored API key (saved to ExtState)
            ai_api_url       = "",  -- custom API base URL
            -- async scan progress
            scanning         = false,  -- true during folder scan (sync + any async AI curl)
            scan_progress    = 0,      -- 0.0–1.0
            scan_stage       = "",     -- description shown to user
            -- async AI curl polling
            ai_polling       = false,  -- true while waiting for background curl
            ai_poll_start    = nil,    -- os.clock() when polling began
            ai_timeout_sec   = 90,     -- max seconds to wait for curl
            ai_req_path      = nil,    -- temp request file (for cleanup)
            ai_out_path      = nil,    -- temp response file (being polled)
            ai_for_all       = false,  -- true = for_all_stems, false = orphans-only
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
            reaper.SetExtState(S, "sidebar_visible", state.sidebar_visible and "1" or "0", true)
            reaper.SetExtState(S, "show_heatmap", state.show_heatmap and "1" or "0", true)
            if #state.recent_guids > 0 then
                reaper.SetExtState(S, "recent_guids",
                    table.concat(state.recent_guids, ","), true)
            else
                reaper.SetExtState(S, "recent_guids", "", true)
            end
            -- Persist UI state to route_map.json (non-critical, best-effort)
            pcall(R.Config.save_state_block, {
                heatmap_visible = state.show_heatmap,
            })
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
            local sv = reaper.GetExtState(S, "sidebar_visible")
            if sv ~= "" then state.sidebar_visible = sv == "1" end
            local hm = reaper.GetExtState(S, "show_heatmap")
            if hm ~= "" then state.show_heatmap = hm == "1" end
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
            if not R.MatchingEngine or not R.MatchingEngine.tokenize then
                log("ERROR: MatchingEngine not loaded. Cannot match stems.")
                return {}
            end
            local config = R.Config.load() or {}
            local guid_map = R.Calibration.get_track_map()  -- returns {guid→track} or nil
            local assignments = {}
            local matched_count = 0
            for idx, stem in ipairs(stems) do
                -- Tokenize ONCE per stem and cache on the stem object (avoids 3x tokenize per stem)
                if not stem._tokens and R.MatchingEngine.tokenize then
                    stem._tokens = R.MatchingEngine.tokenize(stem.name)
                end
                local stem_tokens = stem._tokens
                -- compute display name (first meaningful token) — local, no stem mutation
                local display
                if stem_tokens and #stem_tokens > 0 then
                    display = stem_tokens[1]
                else
                    display = stem.name:gsub("%.[^%.]+$", "")
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
                    display_name = display,  -- cached display name, no stem mutation
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

        -- ── AI config persistence helper (shared by scan_folder and _resolve_ai_only) ─
        local function _save_ai_config()
            -- Deep copy to avoid mutating the live cached config
            local ai_override = {}
            local ai_cfg = R.Config.get_ai_config() or {}
            for k, v in pairs(ai_cfg) do ai_override[k] = v end
            if state.ai_provider ~= "" then ai_override.provider = state.ai_provider end
            if state.ai_model ~= "" then ai_override.model = state.ai_model end
            if state.ai_api_key ~= "" then ai_override.api_key = state.ai_api_key end
            local override_str = R.JSON.stringify(ai_override)
            local ov_file = io.open(R._script_dir .. "ai_config.json", "w")
            if ov_file then ov_file:write(override_str) ov_file:close() end
        end

        -- ── Apply AI JSON mapping to state.assignments ──
        local function _apply_ai_mapping(content, for_all_stems, parse_response)
            if not content or content == "" then
                log("AI: response file was empty")
                return
            end
            local parsed = parse_response(content)
            if not parsed or parsed == "" then
                log("AI: response wasn't valid JSON: " .. (content:sub(1, 120) or "empty"))
                return
            end
            local ok2, mapping = pcall(R.JSON.parse, parsed)
            if not ok2 or not mapping or not mapping.assignments then
                log("AI: response missing assignments field")
                return
            end
            if for_all_stems then
                -- Apply AI assignments to state.assignments immediately
                local stem_by_name = {}
                for i, s in ipairs(state.stems) do stem_by_name[s.name] = i end
                local track_by_name_lower = {}
                for _, t in ipairs(state.available_tracks) do track_by_name_lower[t.name:lower()] = t end
                local changed = 0
                for filename, track_name in pairs(mapping.assignments) do
                    local i = stem_by_name[filename]
                    if i then
                        local t = track_by_name_lower[track_name:lower()]
                        if t then
                            if (state.assignments[i] or {}).name ~= t.name then changed = changed + 1 end
                            state.assignments[i] = {
                                track = t.track, name = t.name,
                                category = "ai", selected = true, reason = "ai", method = "ai",
                            }
                        end
                    end
                end
                if R.Orphan and R.Orphan.collect then
                    state.orphan_data = R.Orphan.collect(state.stems, state.assignments)
                end
                log("AI: updated " .. changed .. " assignment(s) across all stems")
            else
                -- Orphan mode: write mapping.json for import
                local mapping_str = R.JSON.stringify({ assignments = mapping.assignments, status = "success" })
                local mf = io.open(R._script_dir .. "mapping.json", "w")
                if mf then mf:write(mapping_str); mf:close() end
                local count = 0; for _ in pairs(mapping.assignments) do count = count + 1 end
                log("AI: " .. count .. " orphan mapping(s) resolved")
            end
        end

        -- ── Poll for async AI curl result ──
        local function _poll_ai_result()
            if not state.ai_polling then return end
            local rf = io.open(state.ai_out_path, "r")
            if rf then
                local stdout = rf:read("*a"); rf:close()
                pcall(os.remove, state.ai_out_path)
                pcall(os.remove, state.ai_req_path)
                local for_all = state.ai_for_all
                local parse_fn = state.ai_parse_response
                state.ai_polling = false
                state.ai_req_path = nil; state.ai_out_path = nil
                state.ai_parse_response = nil
                if parse_fn then
                    _apply_ai_mapping(stdout, for_all, parse_fn)
                end
                state.scanning = false
                state.scan_progress = 1.0
                state.scan_stage = ""
                state.status = "Ready"
            elseif os.clock() - state.ai_poll_start > state.ai_timeout_sec then
                log("AI: query timed out — check network, API key, and URL")
                pcall(os.remove, state.ai_req_path)
                pcall(os.remove, state.ai_out_path)
                state.ai_polling = false
                state.ai_req_path = nil; state.ai_out_path = nil
                state.ai_parse_response = nil
                state.scanning = false
                state.scan_progress = 1.0
                state.scan_stage = ""
                state.status = "Ready"
            else
                -- Pulse progress while waiting
                local elapsed = os.clock() - state.ai_poll_start
                state.scan_progress = 0.7 + math.min(elapsed / state.ai_timeout_sec * 0.25, 0.25)
                state.scan_stage = "AI: consulting LLM (" .. math.floor(elapsed) .. "s)"
            end
        end

        -- ── AI curl helper (shared by scan_folder and resolve_ai) ──────────
        -- If for_all_stems is true, sends ALL stems for AI review and updates
        -- state.assignments immediately (used during scan). Otherwise only
        -- sends orphans (for Resolve AI button), writes mapping.json for import.
        -- When async=true, launches curl in background and polls via defer loop.
        local function _run_ai_curl(for_all_stems, async)
            if state.ai_api_key == "" then return end
            if not R.JSON or not R.JSON.stringify then return end
            if for_all_stems then
                if not state.stems or #state.stems == 0 then return end
            else
                if not state.orphan_data or state.orphan_data.orphan_count == 0 then return end
            end

            state.status = "AI: querying LLM..."
            local model = (state.ai_model ~= "" and state.ai_model) or "gpt-4o-mini"
            local provider = (state.ai_provider ~= "" and state.ai_provider) or "openai"
            log("AI: consulting " .. model .. " via " .. provider .. "...")

            -- Build prompts
            local stem_entries = {}
            if for_all_stems then
                for i, s in ipairs(state.stems) do
                    local curr = (state.assignments[i] and state.assignments[i].name) or "unmatched"
                    stem_entries[#stem_entries + 1] = "  - " .. s.name .. " [current: " .. curr .. "]"
                end
            else
                for _, o in ipairs(state.orphan_data.orphans) do
                    stem_entries[#stem_entries + 1] = "  - " .. o.stem.name
                end
            end
            local track_names = {}
            for _, t in ipairs(state.available_tracks) do
                track_names[#track_names + 1] = "  - " .. t.name
            end

            local system_prompt
            local user_prompt
            if for_all_stems then
                system_prompt = [[You are a music production assistant specializing in stem routing.
Review and improve stem-to-track assignments. For each stem, confirm the current
assignment or suggest a better track based on musical function.

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
Include EVERY stem in your response. No explanation, no markdown, no commentary.]]
                user_prompt = "Review and improve these stem-to-track assignments.\n\nStems:\n"
                    .. table.concat(stem_entries, "\n")
                    .. "\n\nAvailable tracks:\n" .. table.concat(track_names, "\n")
                    .. "\n\nRespond with the JSON mapping for ALL stems."
            else
                system_prompt = [[You are a music production assistant specializing in stem routing.
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
                user_prompt = "Assign these orphan stems to the most appropriate tracks.\n\nOrphan stems:\n"
                    .. table.concat(stem_entries, "\n")
                    .. "\n\nAvailable tracks:\n" .. table.concat(track_names, "\n")
                    .. "\n\nRespond with the JSON mapping."
            end

            -- Resolve timeout from config (default 60s — generous for slow LLMs)
            local ai_cfg_timeout = (R.Config.get_ai_config() or {}).timeout_seconds or 60
            local timeout_sec = math.max(15, tonumber(ai_cfg_timeout) or 60)

            local base_url = state.ai_api_url
            if base_url == "" then
                if provider == "gemini" then base_url = "https://generativelanguage.googleapis.com/v1beta"
                elseif provider == "opencode" then base_url = "https://api.opencode.ai/v1"
                else base_url = "https://api.openai.com/v1" end
            end
            local function shdq(s)
                return s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("%$", "\\$"):gsub("`", "\\`")
            end

            local req_str, curl_url, curl_auth_header, parse_response
            local is_gemini = provider == "gemini"

            if is_gemini then
                local gemini_req = {
                    contents = {
                        { role = "user", parts = { { text = user_prompt } } },
                    },
                    system_instruction = { parts = { { text = system_prompt } } },
                    generationConfig = { response_mime_type = "application/json", temperature = 0.1 },
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
                local oai_req = {
                    model = model,
                    messages = {
                        { role = "system", content = system_prompt },
                        { role = "user", content = user_prompt },
                    },
                    temperature = 0.1,
                }
                -- JSON mode: only for known OpenAI-compatible providers that support it.
                -- Kilo Gateway's auto-free tier and custom "other" endpoints may route
                -- to models that don't support response_format, so we skip it there.
                local known_json_mode = provider == "openai" or provider == "opencode"
                if known_json_mode then
                    oai_req.response_format = { type = "json_object" }
                end
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

            -- Write request body to a cross-platform temp file
            local req_tag = tostring(os.time()):gsub("%D", "")
            local req_path, out_path
            local os_name = reaper.GetOS and reaper.GetOS() or ""
            if os_name:match("Win") then
                local win_temp = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Temp"
                req_path = win_temp .. "\\grovereq_" .. req_tag .. ".json"
                out_path = win_temp .. "\\groveresp_" .. req_tag .. ".json"
            else
                local tmp_dir = os.getenv("TMPDIR") or os.getenv("TMP") or "/tmp"
                req_path = tmp_dir .. "/grovereq_" .. req_tag .. ".json"
                out_path = tmp_dir .. "/groveresp_" .. req_tag .. ".json"
            end
            local req_f = io.open(req_path, "w")
            if req_f then
                req_f:write(req_str)
                req_f:close()
                local curl_opts = '--max-time ' .. timeout_sec .. ' --connect-timeout 15'
                -- Simple curl command: -d @file (Windows native path), -o outfile, no pipes
                local curl_cmd = 'curl -sS ' .. curl_opts .. ' "' .. shdq(curl_url) .. '"'
                    .. ' -H "Content-Type: application/json"'
                    .. curl_auth_header
                    .. ' -d @"' .. shdq(req_path) .. '" -o "' .. shdq(out_path) .. '"'
                if async then
                    -- Launch curl in background and poll via defer loop
                    local bg_cmd
                    if os_name:match("Win") then
                        bg_cmd = 'start /B "" ' .. curl_cmd
                    else
                        bg_cmd = curl_cmd .. ' &'
                    end
                    os.execute(bg_cmd)
                    -- Set up polling state (response will be processed in _poll_ai_result)
                    state.ai_polling = true
                    state.ai_poll_start = os.clock()
                    state.ai_req_path = req_path
                    state.ai_out_path = out_path
                    state.ai_for_all = for_all_stems
                    state.ai_parse_response = parse_response
                    log("AI: query launched in background")
                else
                    -- Synchronous curl (blocks UI — used only by _resolve_ai_only)
                    local exec_ms = math.min(timeout_sec * 1000 + 5000, 120000)
                    local ret, err_out = reaper.ExecProcess(curl_cmd, exec_ms)
                    pcall(os.remove, req_path)
                    local stdout = ""
                    local rf = io.open(out_path, "r")
                    if rf then stdout = rf:read("*a"); rf:close(); pcall(os.remove, out_path) end
                    if not ret then
                        log("AI: curl command failed — check network, API key, and URL")
                    elseif stdout and stdout ~= "" then
                        _apply_ai_mapping(stdout, for_all_stems, parse_response)
                    else
                        log("AI: response file was empty — ret=" .. tostring(ret))
                    end
                end
            end
        end

        -- ── Lightweight AI re-resolution (preserves manual assignments) ──
        local function _resolve_ai_only()
            if state.ai_api_key == "" then
                log("AI: set an API key first (see AI ASSISTANT section).")
                return
            end
            if not state.orphan_data or state.orphan_data.orphan_count == 0 then
                log("AI: no orphans to resolve.")
                return
            end
            -- Re-export current orphans and re-run AI
            local config = R.Config.load() or {}
            if R.Orphan and R.Orphan.export_for_ai then
                R.Orphan.export_for_ai(state.orphan_data, state.available_tracks, R._script_dir, config)
                _save_ai_config()
            end
            _run_ai_curl()
            -- Apply AI mapping immediately (same logic as do_import)
            if R.Orphan and R.Orphan.check_ai_mapping then
                local mapping = R.Orphan.check_ai_mapping(R._script_dir, state.orphan_data)
                if mapping and mapping.assignments and next(mapping.assignments) then
                    local ai_count = 0
                    for filename, track_name in pairs(mapping.assignments) do
                        local orphan_stem
                        for _, o in ipairs(state.orphan_data.orphans) do
                            if o.stem.name == filename then
                                orphan_stem = o
                                break
                            end
                        end
                        if orphan_stem then
                            for _, t in ipairs(state.available_tracks) do
                                if t.name:lower() == track_name:lower() then
                                    R.Import.insert_media(orphan_stem.stem.path, t.track, nil, config)
                                    state.assignments[orphan_stem.index] = {
                                        track = t.track,
                                        name = t.name,
                                        category = "ai",
                                        selected = false,
                                        reason = "ai",
                                        method = "ai",
                                    }
                                    ai_count = ai_count + 1
                                    break
                                end
                            end
                        end
                    end
                    -- Refresh orphan_data and update UI state
                    if R.Orphan and R.Orphan.collect then
                        state.orphan_data = R.Orphan.collect(state.stems, state.assignments)
                        for _, o in ipairs(state.orphan_data.orphans) do
                            local aa = state.assignments[o.index]
                            if aa then o.selected = aa.selected end
                        end
                    end
                    log("AI assigned " .. ai_count .. " orphan(s)")
                    state.status = "AI resolved " .. ai_count .. " orphan(s)"
                end
            end
        end

        local function scan_folder()
            state.error_msg = nil
            state.scanning = true
            state.scan_progress = 0
            state.status = "Scanning..."
            state.scan_stage = "Scanning folder..."

            local config = R.Config.load() or {}
            local stems = R.Import.scan(state.folder_path)
            if #stems == 0 then
                state.error_msg = "No audio files found in that folder."
                state.stems = {}; state.stem_names = {}
                state.stem_count = 0; state.scanned = false; state.scanning = false
                state.scan_progress = 0; state.scan_stage = ""
                state.status = "Ready"
                log(state.error_msg)
                return
            end
            state.scan_progress = 0.15
            state.scan_stage = "Indexing stems..."

            state.cached_window_h_sidebar = nil
            state.cached_window_h_noside = nil
            state.stems = stems
            state.stem_names = {}
            for _, s in ipairs(stems) do
                state.stem_names[#state.stem_names + 1] = s.name
            end
            state.stem_count = #stems

            state.scan_progress = 0.35
            state.scan_stage = "Collecting tracks..."

            state.available_tracks = collect_tracks()
            state.assignments = run_matching(stems, state.available_tracks)

            state.scan_progress = 0.55
            state.scan_stage = "Identifying orphans..."
            -- Collect orphan data for the orphans section
            if R.Orphan and R.Orphan.collect then
                state.orphan_data = R.Orphan.collect(stems, state.assignments)
                -- Sync bulk-selection state from assignments → orphan entries (scan→import gap)
                for _, o in ipairs(state.orphan_data.orphans) do
                    local a = state.assignments[o.index]
                    if a then o.selected = a.selected end
                end
                log("Matched: " .. state.orphan_data.matched_count .. ", Orphans: " .. state.orphan_data.orphan_count)
            else
                state.orphan_data = nil
                log("Orphan module not loaded — no orphan tracking available.")
            end

            state.scan_progress = 0.70
            state.scan_stage = "AI: consulting LLM..."
            state.status = "AI: querying LLM..."

            -- ── AI: call LLM via background curl (non-blocking) ──────────
            local ai_cfg_key = (R.Config.get_ai_config() or {}).api_key or state.ai_api_key or ""
            local ai_enabled = (ai_cfg_key ~= "" or state.ai_provider ~= "")
            if ai_enabled and R.Orphan and R.Orphan.export_for_ai
               and state.orphan_data and state.orphan_data.orphan_count > 0 then
                R.Orphan.export_for_ai(state.orphan_data, state.available_tracks, R._script_dir, config)
                _save_ai_config()
            end
            _run_ai_curl(true, true)  -- async=true

            -- If no async polling was started (AI disabled or no API key), finish scan immediately
            if not state.ai_polling then
                state.scanning = false
                state.scan_progress = 1.0
                state.scan_stage = ""
                state.status = "Ready"
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
            -- Clone config before mutation to avoid leaking overrides to live config
            local cfg = {}
            for k, v in pairs(config) do cfg[k] = v end
            config = cfg
            config.overflow_behavior = state.overflow_mode
            config.max_lanes_per_track = state.max_lanes

            -- Recompute orphan_data from current assignments (may have changed since scan)
            if R.Orphan and R.Orphan.collect then
                state.orphan_data = R.Orphan.collect(state.stems, state.assignments)
            end

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
                        local guid = tr.guid
                        if not used[guid] then
                            R.Import.insert_media(entry.stem.path, tr.track, nil, config)
                            used[guid] = true; ins = ins + 1
                        else
                            R.Overflow.dispatch(entry.stem, tr.track, config, entry.cat)
                            ovf = ovf + 1
                        end
                    end
                end
            end

            -- After matched imports, create new tracks for selected no-match stems
            if R.Orphan and R.Orphan._create_track_from_orphan then
                for idx, stem in ipairs(state.stems) do
                    local a = state.assignments[idx]
                    if a and a.selected and not a.track then
                        local cfg2 = R.Config.load() or {}
                        local orphan_entry = {
                            stem = stem,
                            category = a.category or "unknown",
                            display = a.display_name or stem.name,
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

            -- Track ALL inserted stems (matched + AI + Create Selected) to prevent AI double-insert
            local inserted_stems = {}
            for idx, stem in ipairs(state.stems) do
                local a = state.assignments[idx]
                if a and a.track and not a.selected then
                    inserted_stems[stem.path] = true
                end
            end

            -- After import loop, try AI mapping for remaining orphans
            if state.orphan_data and state.orphan_data.orphan_count > 0
                and R.Orphan and R.Orphan.check_ai_mapping
                and (state.ai_provider ~= "" or R.Config.get_ai_config().provider ~= "") then
                local mapping = R.Orphan.check_ai_mapping(R._script_dir, state.orphan_data)
                if mapping and mapping.assignments and next(mapping.assignments) then
                    local ai_count = 0
                    for filename, track_name in pairs(mapping.assignments) do
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
                            local found_track = false
                            for _, t in ipairs(state.available_tracks) do
                                if t.name:lower() == track_name:lower() then
                                    if inserted_stems[orphan_stem.stem.path] then
                                        log("AI: skipping " .. filename .. " — already inserted via Create Selected")
                                    else
                                        R.Import.insert_media(orphan_stem.stem.path, t.track, nil, config)
                                        ai_count = ai_count + 1
                                        ins = ins + 1
                                    end
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
                        skip = math.max(0, skip - ai_count)
                        log("AI assigned " .. ai_count .. " orphan(s)")
                    end
                end
            end

            -- Refresh orphan_data after selected-orphan and AI inserts
            if R.Orphan and R.Orphan.collect then
                state.orphan_data = R.Orphan.collect(state.stems, state.assignments)
                for _, o in ipairs(state.orphan_data.orphans) do
                    local aa = state.assignments[o.index]
                    if aa then o.selected = aa.selected end
                end
            end

            reaper.Undo_EndBlock(WINDOW_TITLE, 0)
            reaper.PreventUIRefresh(-1)

            local orphan_count = state.orphan_data and state.orphan_data.orphan_count or 0
            local msg = ins .. " inserted, " .. ovf .. " overflowed, " .. skip .. " skipped"
                .. (orphan_count > 0
                    and (", " .. orphan_count .. " remaining orphan(s)")
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

        -- ── track selection helper (deduplicates combo handler code) ────
        local function _select_track_for_stem(idx, t)
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
            -- Wire Learning.record_corrections() after manual reassignment
            if R.Learning and R.Learning.record_corrections then
                pcall(R.Learning.record_corrections, state.assignments)
            end
            save_prefs()
        end

        -- ── defer render loop ──────────────────────────────────────────
        local function loop()
            local ok_loop, loop_err = xpcall(function()
            -- (loop body is now inside xpcall to catch runtime errors)
            -- error handler: debug.traceback includes line numbers in loop_err
            -- (passed via xpcall's second argument)

            -- Poll for async AI curl result every frame
            _poll_ai_result()

            local show_sidebar = state.sidebar_visible and (state.show_manifest or (state.scanned and #state.stems > 0))
            -- Track sidebar state change to force window resize
            local sidebar_was_visible = state._sidebar_was_visible
            if sidebar_was_visible == nil then sidebar_was_visible = show_sidebar end
            local sidebar_toggled = (sidebar_was_visible ~= show_sidebar)
            state._sidebar_was_visible = show_sidebar

            -- widen minimum when sidebar is active
            local eff_min_w = min_w
            if show_sidebar then
                eff_min_w = math.max(eff_min_w, min_w + 324 + 4)
            end
            -- Force window width when sidebar toggles (constraints alone don't resize)
            if sidebar_toggled then
                ImGui.ImGui_SetNextWindowSize(ctx, eff_min_w, -1)
            end
            -- window: fixed width (sidebar-aware). Height = per-sidebar-state cached or auto.
            local min_h, max_h
            if show_sidebar then
                if state.cached_window_h_sidebar then
                    min_h = state.cached_window_h_sidebar; max_h = state.cached_window_h_sidebar
                else
                    min_h = state.scanned and 590 or 395; max_h = 9999
                end
            else
                if state.cached_window_h_noside then
                    min_h = state.cached_window_h_noside; max_h = state.cached_window_h_noside
                else
                    min_h = state.scanned and 590 or 395; max_h = 9999
                end
            end
            ImGui.ImGui_SetNextWindowSizeConstraints(ctx, eff_min_w, min_h, eff_min_w, max_h)
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
                            state.cached_window_h_sidebar = nil
                            state.cached_window_h_noside = nil
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
                    save_prefs()
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

                    -- Provider dropdown (includes "other" for custom OpenAI-compatible endpoints)
                    ImGui.ImGui_SetNextItemWidth(ctx, -80)
                    if ImGui.ImGui_BeginCombo(ctx, "##provider", cur_provider) then
                        local providers = {"openai", "opencode", "gemini", "other"}
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

                    -- Align API label + input fields so they start at the same X
                    local key_sz = ImGui.ImGui_CalcTextSize(ctx, "API Key:")
                    local url_sz = ImGui.ImGui_CalcTextSize(ctx, "API URL:")
                    local ai_lbl_w = math.max(key_sz or 0, url_sz or 0)

                    -- API Key (masked by ImGui InputTextFlags_Password, value stays real)
                    ImGui.ImGui_AlignTextToFramePadding(ctx)
                    local lbl_x = ImGui.ImGui_GetCursorPosX(ctx)
                    ImGui.ImGui_Text(ctx, "API Key:")
                    ImGui.ImGui_SameLine(ctx, lbl_x + ai_lbl_w + 8)
                    ImGui.ImGui_SetNextItemWidth(ctx, -1)
                    local ch_k, new_key = ImGui.ImGui_InputText(ctx, "##api_key", state.ai_api_key,
                        ImGui.ImGui_InputTextFlags_Password())
                    if ch_k then
                        state.ai_api_key = new_key
                        save_prefs()
                    end

                    -- API URL (editable, with provider-appropriate default)
                    ImGui.ImGui_AlignTextToFramePadding(ctx)
                    lbl_x = ImGui.ImGui_GetCursorPosX(ctx)
                    ImGui.ImGui_Text(ctx, "API URL:")
                    ImGui.ImGui_SameLine(ctx, lbl_x + ai_lbl_w + 8)
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

                -- Progress bar during async scan
                if state.scanning or state.ai_polling then
                    local bar_w = ImGui.ImGui_GetContentRegionAvail(ctx)
                    local bx, by = ImGui.ImGui_GetCursorScreenPos(ctx)
                    local bar_h = 16
                    local ok_dl, dl = pcall(ImGui.ImGui_GetWindowDrawList, ctx)
                    if ok_dl and dl then
                        ImGui.ImGui_DrawList_AddRectFilled(dl, bx, by, bx + bar_w, by + bar_h, 0x66000000, 4)
                        local fill_w = bar_w * math.min(state.scan_progress, 1)
                        if fill_w > 4 then
                            ImGui.ImGui_DrawList_AddRectFilled(dl, bx, by, bx + fill_w, by + bar_h, 0xE033AA55, 4)
                        end
                    end
                    ImGui.ImGui_SetCursorPosY(ctx, by + bar_h + 2)
                    ImGui.ImGui_Text(ctx, state.scan_stage)
                end

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
local sb_start_y = ImGui.ImGui_GetCursorPosY(ctx)
ImGui.ImGui_Separator(ctx)

-- MANIFEST
if state.show_manifest then
    local sb_header_h = ImGui.ImGui_GetCursorPosY(ctx) - sb_start_y
    local sb_avail = sb_full_h - sb_header_h
    local man_h = math.max(60, math.floor(sb_avail * 0.4))
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
                        -- Heatmap toggle button
                        ImGui.ImGui_Text(ctx, "STEMS (" .. state.stem_count .. ")")
                        ImGui.ImGui_SameLine(ctx, 0, 4)
                        if ImGui.ImGui_Button(ctx, state.show_heatmap and "☰ List" or "▦ Heatmap", 0) then
                            state.show_heatmap = not state.show_heatmap
                        end
                        ImGui.ImGui_SameLine(ctx, 0, 4)
                        ImGui.ImGui_Text(ctx, "— click track to reassign")
                        local to_delete = {}

                        -- Heatmap view
                        if state.show_heatmap then
                            local hm_cols = {"Stem"}
                            for _, t in ipairs(state.available_tracks) do
                                hm_cols[#hm_cols + 1] = t.name:sub(1, 8)
                            end
                            local hm_h = math.min(#state.stems * 18 + 30, 300)
                            if ImGui.ImGui_BeginChild(ctx, "##heatmap", 0, hm_h, ImGui.ImGui_ChildFlags_Borders()) then
                                -- Header row
                                ImGui.ImGui_Text(ctx, "Stem")
                                for ci = 2, #hm_cols do
                                    ImGui.ImGui_SameLine(ctx, ci * 60, 2)
                                    ImGui.ImGui_TextDisabled(ctx, hm_cols[ci])
                                end
                                -- Data rows
                                for idx, stem in ipairs(state.stems) do
                                    local a = state.assignments[idx]
                                    local matched_name = a and a.name or ""
                                    ImGui.ImGui_Text(ctx, stem.name:sub(1, 16))
                                    for ti, t in ipairs(state.available_tracks) do
                                        local is_match = (matched_name == t.name)
                                        ImGui.ImGui_SameLine(ctx, ti * 60 + 55, 2)
                                        if is_match then
                                            ImGui.ImGui_Text(ctx, "●")
                                        else
                                            ImGui.ImGui_TextDisabled(ctx, "·")
                                        end
                                    end
                                end
                            end
                            ImGui.ImGui_EndChild(ctx)
                            ImGui.ImGui_Separator(ctx)
                        end

                        -- Sticky header (does not scroll with stems)
                        local cb_col_w = 24
                        local max_stem_w = 0
                        for _, s in ipairs(state.stems) do
                            local w = ImGui.ImGui_CalcTextSize(ctx, s.name) or 0
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
                            if not R.Orphan or not R.Orphan._create_track_from_orphan then
                                log("Orphan module not loaded.")
                            else
                                local cfg = R.Config.load() or {}
                                local n = 0
                                for idx, stem in ipairs(state.stems) do
                                    local a = state.assignments[idx]
                                    if a and a.selected and not a.track then
                                        local o = {stem=stem, category=a.category or "unknown",
                                                   display=a.display_name or stem.name, reason=a.reason or "no match"}
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
                                    state.available_tracks = collect_tracks()
                                else
                                    log("No stems selected — check the box next to a stem first.")
                                end
                            end  -- guard else
                        end  -- "Create Sel" button
                        ImGui.ImGui_SameLine(ctx, 0, 4)
                        if ImGui.ImGui_Button(ctx, "New trk", 44) then
                            reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
                            state.available_tracks = collect_tracks()
                        end
                        ImGui.ImGui_SameLine(ctx, 0, 4)
                        if ImGui.ImGui_Button(ctx, "Resolve AI", 0) then
                            _resolve_ai_only()
                        end
                        ImGui.ImGui_Separator(ctx)

                        local stems_avail = select(2, ImGui.ImGui_GetContentRegionAvail(ctx))
                        local stems_h = math.max(60, stems_avail - 4)
                        local stems_flags = (not state.sidebar_visible and not state.show_manifest) and ImGui.ImGui_ChildFlags_Borders() or 0
local sv = ImGui.ImGui_BeginChild(ctx, "##stems", 0, stems_h, 0, stems_flags)
                        if sv then
                            -- orphan count at TOP
                            local orphan_count = 0
                            for _, a in ipairs(state.assignments) do
                                if not a.track then orphan_count = orphan_count + 1 end
                            end
                            if orphan_count > 0 then
                                ImGui.ImGui_Text(ctx, "ORPHANS (" .. orphan_count .. ") — no track match")
                            end
                            -- Lazy-load: render in chunks of 50 based on scroll
                            local scroll_y = ImGui.ImGui_GetScrollY(ctx)
                            local scroll_max = ImGui.ImGui_GetScrollMaxY(ctx) or 1
                            local visible_ratio = scroll_y / math.max(scroll_max, 1)
                            local chunk_size = 50
                            local total_stems = #state.stems
                            local start_idx = math.max(1, math.floor(visible_ratio * total_stems) - chunk_size / 2 + 1)
                            local end_idx = math.min(total_stems, start_idx + chunk_size - 1)
                            for idx = start_idx, end_idx do
                                local stem = state.stems[idx]
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
                                local nw = ImGui.ImGui_CalcTextSize(ctx, stem.name) or 0
                                local display_name = stem.name
                                if nw > name_avail then
                                    for i = #stem.name - 1, 3, -1 do
                                        local sub = stem.name:sub(1, i) .. ".."
                                        local tw = ImGui.ImGui_CalcTextSize(ctx, sub) or 0
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
                                            _select_track_for_stem(idx, t)
                                        end
                                    end
                                    if has_recent and has_rest then
                                        ImGui.ImGui_Separator(ctx)
                                    end
                                    for _, t in ipairs(rest) do
                                        local sel = a and a.track == t.track or false
                                        if ImGui.ImGui_Selectable(ctx, t.name, sel) then
                                            _select_track_for_stem(idx, t)
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
                    -- Cache window height separately for sidebar-visible and sidebar-hidden states
                    if show_sidebar then
                        if not state.cached_window_h_sidebar then
                            state.cached_window_h_sidebar = main_h + chrome_h
                        end
                    else
                        if not state.cached_window_h_noside then
                            state.cached_window_h_noside = main_h + chrome_h
                        end
                    end
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
            end, debug.traceback)  -- xpcall close (debug.traceback adds line numbers)
            if not ok_loop then
                reaper.ShowConsoleMsg("Grove GUI error: " .. tostring(loop_err) .. "\n")
                reaper.ShowMessageBox("Grove Stem Auto-Router error:\n\n" .. tostring(loop_err) .. "\n\nSee View → Console for details.", "Grove Error", 0)
                -- Re-schedule the loop so the GUI recovers from transient errors instead of dying
                reaper.defer(loop)
            end
        end

        -- ── bootstrap ────────────────────────────────────────────────────
        -- Initial size: constraints drive width+height auto-fit on first frame
        -- (no SetNextWindowSize — ImGui auto-sizes to contain all elements)
        load_prefs()

        -- greet + cleanup stale orphan/AI files from previous runs
        pcall(os.remove, R._script_dir .. "orphans.json")
        pcall(os.remove, R._script_dir .. "_ai_request.json")
        local stale_map = io.open(R._script_dir .. "mapping.json", "r")
        if stale_map then stale_map:close(); pcall(os.remove, R._script_dir .. "mapping.json") end

        local cfg = R.Config.load()
        if cfg then
            state.overflow_mode = cfg.overflow_behavior or "lanes"
            state.max_lanes = cfg.max_lanes_per_track or state.max_lanes or 0
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
