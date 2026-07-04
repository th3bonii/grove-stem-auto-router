-- Grove Stem Auto-Router / lib/fuzzy.lua
-- Pure Levenshtein edit distance and token/track fuzzy matching
-- Depends on: nothing (pure functions, no R deps)
--
-- Usage:
--   local dist = R.Fuzzy.levenshtein("kicck", "kick")  -- → 1
--   local track, score = R.Fuzzy.match_best(
--     {"sub", "bass"}, {"Sub Bass", "Kick"}, 0.8
--   )  -- → "Sub Bass", 0.83...

return function(R)
    R.Fuzzy = {}

    --- Compute Levenshtein edit distance between two strings.
    -- Standard dynamic-programming implementation.
    -- Returns the minimum number of single-character edits (insert, delete, substitute).
    -- @param a string
    -- @param b string
    -- @return int — edit distance
    function R.Fuzzy.levenshtein(a, b)
        if a == b then return 0 end
        local a_len, b_len = #a, #b
        if a_len == 0 then return b_len end
        if b_len == 0 then return a_len end

        -- Build the distance matrix
        -- NOTE: {i} in Lua creates {[1]=i}, not {[0]=i} — must set [0] explicitly
        local matrix = {}
        for i = 0, a_len do
            matrix[i] = {[0] = i}
        end
        for j = 0, b_len do
            matrix[0][j] = j
        end

        for i = 1, a_len do
            for j = 1, b_len do
                local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
                matrix[i][j] = math.min(
                    matrix[i - 1][j] + 1,        -- deletion
                    matrix[i][j - 1] + 1,        -- insertion
                    matrix[i - 1][j - 1] + cost   -- substitution
                )
            end
        end

        return matrix[a_len][b_len]
    end

    --- Find the best fuzzy match for stem tokens against track names.
    -- Compares each stem token against each track name using Levenshtein distance,
    -- normalized by the longer string's length: score = 1 - (dist / max_len).
    -- Returns the best match that meets the threshold.
    -- @param stem_tokens table — array of lowercase stem tokens
    -- @param track_names table — array of track name strings (will be lowercased internally)
    -- @param threshold number — minimum score to accept (default 0.8)
    -- @return string|nil — best matching track name
    -- @return number — best score (0 if no match)
    function R.Fuzzy.match_best(stem_tokens, track_names, threshold)
        threshold = threshold or 0.8
        local best_score, best_track = 0, nil

        for _, track_name in ipairs(track_names) do
            local t_lower = track_name:lower()
            for _, stem_token in ipairs(stem_tokens) do
                local dist = R.Fuzzy.levenshtein(stem_token, t_lower)
                local max_len = math.max(#stem_token, #track_name)
                local score = max_len > 0 and math.min(1.0, math.max(0.0, 1 - dist / max_len)) or 0
                if score > best_score and score >= threshold then
                    best_score = score
                    best_track = track_name
                end
            end
        end

        return best_track, best_score
    end
end
