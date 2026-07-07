-- Grove Stem Auto-Router / lib/fuzzy.lua
-- Pure Levenshtein edit distance (used by matching-engine inline fuzzy fallback)
-- Depends on: nothing (pure functions, no R deps)
--
-- Usage:
--   local dist = R.Fuzzy.levenshtein("kicck", "kick")  -- → 1

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
end
