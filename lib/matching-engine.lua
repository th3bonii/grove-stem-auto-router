-- Grove Stem Auto-Router / lib/matching-engine.lua
-- Token-intersection matching engine with GUID priority and fuzzy fallback
-- Depends on: R.Config, R.Fuzzy (both loaded before this is called at runtime)
--
-- Priority chain: calibrated GUID → token-intersection → fuzzy → orphan/nil
--
-- Usage:
--   local result = R.MatchingEngine.match(stem_name, tracks, config, guid_map)
--   if result then
--     local track, name, method = result
--     -- method is "calibrated", "token-intersection", or "fuzzy"
--   end

return function(R)
    R.MatchingEngine = {}

    --- Split a stem or track name into normalized tokens.
    -- Strips extension, splits CamelCase/PascalCase boundaries, replaces
    -- separators with spaces, lowercases, filters out pure numbers and
    -- keywords_ignore tokens.
    -- @param name string — filename or track name
    -- @return table — array of normalized string tokens
    function R.MatchingEngine.tokenize(name)
        local base = name:gsub("%.[^%.]+$", "")  -- remove extension
        -- Split on lowercase→uppercase boundary only (e.g. "ClosedHat" → "Closed Hat").
        -- Avoid splitting single-letter prefixes: "OHat" stays as "ohat" so alias entries
        -- like "ohat" → "hhat" still work. "FXHat" stays as one token too.
        local case_split = base:gsub("(%l)(%u)", "%1 %2")
        local cleaned = case_split:gsub("[_%-%.]", " "):lower()
        local tokens = {}
        for token in cleaned:gmatch("%S+") do
            -- skip pure numbers
            if not token:match("^%d+$") then
                tokens[#tokens + 1] = token
            end
        end
        -- Apply keywords_ignore
        local ignore = R.Config.get_ignore_set()
        local filtered = {}
        for _, t in ipairs(tokens) do
            if not ignore[t] then
                filtered[#filtered + 1] = t
            end
        end
        return filtered
    end

    --- Resolve tokens through the alias map.
    -- Each token is looked up in the alias map. If found, it is replaced
    -- with the canonical category name. Otherwise the original token is kept.
    -- @param tokens table — array of string tokens from tokenize()
    -- @param config table — route_map config (unused, kept for API consistency)
    -- @return table — resolved tokens
    -- @return string|nil — first alias value found, or nil
    function R.MatchingEngine.resolve(tokens, config)
        local alias_map = R.Config.get_alias_map()
        local resolved = {}
        local first_alias = nil
        for _, token in ipairs(tokens) do
            local mapped = alias_map[token]
            if mapped then
                resolved[#resolved + 1] = mapped
                if not first_alias then first_alias = mapped end
            else
                resolved[#resolved + 1] = token
            end
        end
        return resolved, first_alias
    end

    --- Compute token-intersection score: shared tokens / min(a, b).
    -- Each stem token is matched at most once against track tokens.
    -- Returns 0 if either set is empty.
    -- @param stem_resolved table — resolved stem tokens
    -- @param track_resolved table — resolved track tokens
    -- @return number — score in [0, 1]
    function R.MatchingEngine.score(stem_resolved, track_resolved)
        if #stem_resolved == 0 or #track_resolved == 0 then return 0 end
        local shared = 0
        for _, s_token in ipairs(stem_resolved) do
            for _, t_token in ipairs(track_resolved) do
                if s_token == t_token then
                    shared = shared + 1
                    break  -- count each stem token at most once
                end
            end
        end
        return math.min(1.0, shared / math.min(#stem_resolved, #track_resolved))
    end

    --- Main matching function.
    -- Implements the priority chain:
    --   1. Calibrated GUID → token-intersection on calibrated tracks (threshold 0.2)
    --   2. Token-intersection on all tracks (threshold 0.5)
    --   3. Fuzzy Levenshtein fallback (threshold from config, default 0.8)
    --   4. Orphan (nil)
    --
    -- @param stem_name string — original stem filename
    -- @param tracks table — array of { track, name, guid } from collect_tracks()
    -- @param config table — route_map config (passed through to resolve)
    -- @param guid_map table|nil — { guid → track } from Calibration.get_track_map()
    -- @return reaper.MediaTrack|nil — matched track
    -- @return string|nil — track display name
    -- @return string|nil — match method: "calibrated", "token-intersection", "fuzzy", or nil
    function R.MatchingEngine.match(stem_name, tracks, config, guid_map)
        -- Step 1: Tokenize and resolve the stem name
        local stem_tokens = R.MatchingEngine.tokenize(stem_name)
        if #stem_tokens == 0 then return nil, nil, nil end
        local stem_resolved, _ = R.MatchingEngine.resolve(stem_tokens, config)
        if #stem_resolved == 0 then return nil, nil, nil end

        -- Step 2: Calibrated matching — only if guid_map is provided
        if guid_map then
            local best_cal_score = 0
            local best_cal_track = nil
            local best_cal_name = nil
            for _, t in ipairs(tracks) do
                if guid_map[t.guid] then  -- this track is in the calibration set
                    local cal_tokens = R.MatchingEngine.tokenize(t.name)
                    local cal_resolved, _ = R.MatchingEngine.resolve(cal_tokens, config)
                    local cal_score = R.MatchingEngine.score(stem_resolved, cal_resolved)
                    if cal_score > best_cal_score then
                        best_cal_score = cal_score
                        best_cal_track = t.track
                        best_cal_name = t.name
                    end
                end
            end
            -- threshold 0.2 = at least one shared token for any reasonable token count
            if best_cal_score > 0.2 then
                return best_cal_track, best_cal_name, "calibrated"
            end
        end

        -- Step 3: Token-intersection against all tracks
        local best_score = 0
        local best_track = nil
        local best_name = nil
        for _, t in ipairs(tracks) do
            local t_tokens = R.MatchingEngine.tokenize(t.name)
            local t_resolved, _ = R.MatchingEngine.resolve(t_tokens, config)
            local token_score = R.MatchingEngine.score(stem_resolved, t_resolved)
            if token_score > best_score then
                best_score = token_score
                best_track = t.track
                best_name = t.name
            end
        end
        -- threshold 0.5 = at least one shared token out of two typical tokens
        if best_score >= 0.5 then
            return best_track, best_name, "token-intersection"
        end

        -- Step 4: Fuzzy fallback — Levenshtein distance per token pair
        -- Compares each resolved stem token against each RAW (unresolved) track token,
        -- so "percs" scores 0.8 against "perc" instead of 0.2 against "drums".
        -- The raw track tokens preserve the actual track name parts for fuzzy matching.
        if R.Fuzzy and R.Fuzzy.levenshtein then
            local fuzzy_threshold = R.Config.get_fuzzy_threshold()
            local best_fuzzy_score = 0
            local best_fuzzy_track = nil
            local best_fuzzy_name = nil
            for _, t in ipairs(tracks) do
                local t_tokens = R.MatchingEngine.tokenize(t.name)
                -- use RAW track tokens for fuzzy — resolved tokens lose specificity
                for _, s_token in ipairs(stem_resolved) do
                    for _, t_token in ipairs(t_tokens) do
                        local dist = R.Fuzzy.levenshtein(s_token, t_token)
                        local max_len = math.max(#s_token, #t_token)
                        local fuzzy_score = max_len > 0 and (1 - dist / max_len) or 0
                        if fuzzy_score > best_fuzzy_score and fuzzy_score >= fuzzy_threshold then
                            best_fuzzy_score = fuzzy_score
                            best_fuzzy_track = t.track
                            best_fuzzy_name = t.name
                        end
                    end
                end
            end
            if best_fuzzy_track then
                return best_fuzzy_track, best_fuzzy_name, "fuzzy"
            end
        end

        -- Step 5: No match — orphan
        return nil, nil, nil
    end

    -- Alias for backward compatibility with design docs
    R.MatchingEngine._token_interscore = R.MatchingEngine.score
end
