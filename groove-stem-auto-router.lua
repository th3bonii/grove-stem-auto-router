--[[
    Grove Stem Auto-Router
    ======================
    Automatically route stem audio files to matching REAPER tracks
    based on filename analysis and route_map configuration.

    Phase 1: JSON Parser & Config
    - Inline recursive-descent JSON parser (zero dependencies)
    - Config loader: parse route_map.json, validate schema, merge defaults
    - Per-category overflow_behavior resolution

    Modules (all attached to R.*):
      R.Config         - route_map.json loader + schema validation (Phase 1)
      R.parse_json     - inline JSON parser utility (Phase 1)
      R.Calibration    - GUID persistence for track disambiguation (Phase 2)
      R.Import         - file scanning, normalization, matching (Phase 3)
      R.Overflow       - lane or new-track overflow dispatch (Phase 4)

    Usage:
      Place side-by-side with route_map.json in REAPER Scripts directory.
      Run from Actions list or SWS cycle action.
]]

-- Capture script source path early for config file discovery
-- REAPER prefixes script source with "@"; strip it and normalize
local _script_source = debug.getinfo(1, "S").source or ""
if _script_source:sub(1, 1) == "@" then
    _script_source = _script_source:sub(2)
end
_script_source = _script_source:gsub("\\", "/")
local _script_dir = _script_source:match("^(.*/)") or ""

-- Module table: all subsystems attach here
local R = {}

-- ════════════════════════════════════════════════════════════════════════
-- INLINE JSON PARSER
-- ════════════════════════════════════════════════════════════════════════

--- Parse a JSON string into a Lua value.
-- Recursive-descent parser supporting objects, arrays, strings,
-- numbers, booleans, and null. Zero external dependencies.
-- @param str (string) JSON input
-- @return (value, nil) on success, (nil, error_msg) on failure
function R.parse_json(str)
    local pos = 1

    -- Skip whitespace: space, tab, LF, CR
    local function skip_ws()
        while pos <= #str do
            local c = str:byte(pos)
            if c == 32 or c == 9 or c == 10 or c == 13 then   -- ' ', \\t, \\n, \\r
                pos = pos + 1
            else
                break
            end
        end
    end

    -- Forward declarations for mutual recursion
    local parse_value, parse_object, parse_array
    local parse_string, parse_number

    -- Dispatch to type-specific parser based on the first character
    parse_value = function()
        skip_ws()
        if pos > #str then
            return nil, "unexpected end of input"
        end
        local c = str:byte(pos)
        if c == 123 then        -- '{'
            return parse_object()
        elseif c == 91 then     -- '['
            return parse_array()
        elseif c == 34 then     -- '"'
            return parse_string()
        elseif c == 116 then    -- 't' (true)
            if str:sub(pos, pos + 3) ~= "true" then
                return nil, string.format("unexpected token at position %d", pos)
            end
            pos = pos + 4
            return true
        elseif c == 102 then    -- 'f' (false)
            if str:sub(pos, pos + 4) ~= "false" then
                return nil, string.format("unexpected token at position %d", pos)
            end
            pos = pos + 5
            return false
        elseif c == 110 then    -- 'n' (null)
            if str:sub(pos, pos + 3) ~= "null" then
                return nil, string.format("unexpected token at position %d", pos)
            end
            pos = pos + 4
            return nil          -- Lua nil represents JSON null
        elseif c == 45 or (c >= 48 and c <= 57) then  -- '-' or '0'-'9'
            return parse_number()
        else
            return nil, string.format("unexpected character '%c' (0x%02X) at position %d", c, c, pos)
        end
    end

    --- Parse a JSON string (enclosed in double quotes).
    -- Handles all standard escape sequences: \\", \\\\, \\/, \\b, \\f, \\n, \\r, \\t, \\uXXXX
    parse_string = function()
        if str:byte(pos) ~= 34 then     -- '"'
            return nil, string.format("expected string opening '\"' at position %d", pos)
        end
        pos = pos + 1   -- skip opening quote
        local parts = {}
        while pos <= #str do
            local c = str:byte(pos)
            if c == 34 then             -- closing '"'
                pos = pos + 1
                return table.concat(parts)
            elseif c == 92 then         -- '\\' escape
                pos = pos + 1
                if pos > #str then
                    return nil, "unterminated escape sequence in string"
                end
                local esc = str:byte(pos)
                if esc == 34 then       -- \\"
                    parts[#parts + 1] = '"'
                elseif esc == 92 then   -- \\\\
                    parts[#parts + 1] = "\\"
                elseif esc == 47 then   -- \\/
                    parts[#parts + 1] = "/"
                elseif esc == 98 then   -- \\b
                    parts[#parts + 1] = "\b"
                elseif esc == 102 then  -- \\f
                    parts[#parts + 1] = "\f"
                elseif esc == 110 then  -- \\n
                    parts[#parts + 1] = "\n"
                elseif esc == 114 then  -- \\r
                    parts[#parts + 1] = "\r"
                elseif esc == 116 then  -- \\t
                    parts[#parts + 1] = "\t"
                elseif esc == 117 then  -- \\uXXXX (Unicode escape)
                    local hex = str:sub(pos + 1, pos + 4)
                    if #hex < 4 then
                        return nil, "invalid \\uXXXX escape: insufficient hex digits"
                    end
                    local code = tonumber(hex, 16)
                    if not code then
                        return nil, "invalid \\uXXXX escape: non-hex characters"
                    end
                    pos = pos + 4
                    -- Encode unicode codepoint to UTF-8 byte sequence
                    if code < 0x80 then
                        parts[#parts + 1] = string.char(code)
                    elseif code < 0x800 then
                        parts[#parts + 1] = string.char(
                            0xC0 + math.floor(code / 0x40),
                            0x80 + (code % 0x40)
                        )
                    else
                        parts[#parts + 1] = string.char(
                            0xE0 + math.floor(code / 0x1000),
                            0x80 + (math.floor(code / 0x40) % 0x40),
                            0x80 + (code % 0x40)
                        )
                    end
                else
                    return nil, string.format("invalid escape sequence '\\\\%c' at position %d", esc, pos)
                end
                pos = pos + 1
            elseif c < 32 then
                -- Control characters (0x00-0x1F) are not allowed in JSON strings
                return nil, string.format("invalid control character 0x%02X in string at position %d", c, pos)
            else
                parts[#parts + 1] = string.char(c)
                pos = pos + 1
            end
        end
        return nil, "unterminated string (missing closing quote)"
    end

    --- Parse a JSON number (integer, float, scientific notation).
    parse_number = function()
        local start = pos
        -- Optional minus sign
        if str:byte(pos) == 45 then     -- '-'
            pos = pos + 1
        end
        if pos > #str then
            return nil, "unexpected end of number"
        end
        local c = str:byte(pos)
        if c == 48 then                 -- '0' (leading zero)
            pos = pos + 1
        elseif c >= 49 and c <= 57 then -- '1'-'9'
            pos = pos + 1
            while pos <= #str do
                c = str:byte(pos)
                if c >= 48 and c <= 57 then
                    pos = pos + 1
                else
                    break
                end
            end
        else
            return nil, string.format("invalid number at position %d: expected digit", start)
        end
        -- Optional fractional part
        if pos <= #str and str:byte(pos) == 46 then  -- '.'
            pos = pos + 1
            if pos > #str then
                return nil, "unexpected end of number after decimal point"
            end
            c = str:byte(pos)
            if c < 48 or c > 57 then
                return nil, "expected digit after decimal point"
            end
            while pos <= #str do
                c = str:byte(pos)
                if c >= 48 and c <= 57 then
                    pos = pos + 1
                else
                    break
                end
            end
        end
        -- Optional exponent part
        if pos <= #str then
            c = str:byte(pos)
            if c == 69 or c == 101 then  -- 'E' or 'e'
                pos = pos + 1
                if pos <= #str then
                    local sign = str:byte(pos)
                    if sign == 43 or sign == 45 then  -- '+' or '-'
                        pos = pos + 1
                    end
                end
                if pos > #str then
                    return nil, "unexpected end of number after exponent"
                end
                local d = str:byte(pos)
                if d < 48 or d > 57 then
                    return nil, "expected digit in exponent"
                end
                while pos <= #str do
                    d = str:byte(pos)
                    if d >= 48 and d <= 57 then
                        pos = pos + 1
                    else
                        break
                    end
                end
            end
        end
        local num_str = str:sub(start, pos - 1)
        local num = tonumber(num_str)
        if num == nil then
            return nil, string.format("invalid number literal '%s' at position %d", num_str, start)
        end
        return num
    end

    --- Parse a JSON object: { "key": value, ... }
    parse_object = function()
        pos = pos + 1   -- skip '{'
        local obj = {}
        skip_ws()
        -- Empty object
        if pos <= #str and str:byte(pos) == 125 then  -- '}'
            pos = pos + 1
            return obj
        end
        local expect_comma = false
        while pos <= #str do
            skip_ws()
            -- Allow trailing comma: }
            if str:byte(pos) == 125 then
                pos = pos + 1
                return obj
            end
            if expect_comma then
                if str:byte(pos) ~= 44 then             -- ','
                    return nil, string.format("expected ',' or '}' in object at position %d", pos)
                end
                pos = pos + 1
                skip_ws()
                -- Handle trailing comma after comma
                if str:byte(pos) == 125 then
                    pos = pos + 1
                    return obj
                end
            end
            expect_comma = true
            -- Key must be a string
            if str:byte(pos) ~= 34 then  -- '"'
                return nil, string.format("expected string key in object at position %d", pos)
            end
            local key, err = parse_string()
            if not key then
                return nil, err
            end
            skip_ws()
            -- Colon separator
            if pos > #str or str:byte(pos) ~= 58 then   -- ':'
                return nil, string.format("expected ':' after object key at position %d", pos)
            end
            pos = pos + 1
            -- Value
            local val, err2 = parse_value()
            if err2 then
                return nil, err2
            end
            obj[key] = val
        end
        return nil, "unterminated object (missing '}')"
    end

    --- Parse a JSON array: [ value, ... ]
    parse_array = function()
        pos = pos + 1   -- skip '['
        local arr = {}
        skip_ws()
        -- Empty array
        if pos <= #str and str:byte(pos) == 93 then  -- ']'
            pos = pos + 1
            return arr
        end
        local expect_comma = false
        while pos <= #str do
            skip_ws()
            -- Allow trailing comma: ]
            if str:byte(pos) == 93 then
                pos = pos + 1
                return arr
            end
            if expect_comma then
                if str:byte(pos) ~= 44 then             -- ','
                    return nil, string.format("expected ',' or ']' in array at position %d", pos)
                end
                pos = pos + 1
                skip_ws()
                -- Handle trailing comma after comma
                if str:byte(pos) == 93 then
                    pos = pos + 1
                    return arr
                end
            end
            expect_comma = true
            local val, err = parse_value()
            if err then
                return nil, err
            end
            arr[#arr + 1] = val
        end
        return nil, "unterminated array (missing ']')"
    end

    -- === Main parse entry ===
    skip_ws()
    if pos > #str then
        return nil, "empty input"
    end
    local result, err = parse_value()
    if err then
        return nil, err
    end
    -- Ensure no trailing content
    skip_ws()
    if pos <= #str then
        return nil, string.format("unexpected trailing content at position %d", pos)
    end
    return result, nil
end

-- ════════════════════════════════════════════════════════════════════════
-- CONFIG MODULE
-- ════════════════════════════════════════════════════════════════════════

R.Config = {}

-- Internal stored configuration (set by load(), read by get_overflow)
R.Config._data = nil

--- Built-in default configuration used when route_map.json is missing or invalid.
-- @return table with all required keys populated
function R.Config._defaults()
    return {
        alias = {},
        keywords_ignore = {},
        overflow_behavior = "lanes",
        max_lanes_per_track = 4,
        categories = {}
    }
end

--- Validate a parsed route_map configuration against the schema.
-- @param config table - the parsed configuration to validate
-- @return (true, nil) if valid, (false, error_msg) if invalid
function R.Config._validate(config)
    if type(config) ~= "table" then
        return false, "root value must be an object"
    end
    if config.alias == nil then
        return false, "missing required key: 'alias'"
    end
    if type(config.alias) ~= "table" then
        return false, "'alias' must be an object (string -> string)"
    end
    if config.keywords_ignore == nil then
        return false, "missing required key: 'keywords_ignore'"
    end
    if type(config.keywords_ignore) ~= "table" then
        return false, "'keywords_ignore' must be an array"
    end
    if config.overflow_behavior == nil then
        return false, "missing required key: 'overflow_behavior'"
    end
    if config.overflow_behavior ~= "lanes" and config.overflow_behavior ~= "new_track" then
        return false, "'overflow_behavior' must be \"lanes\" or \"new_track\""
    end
    if config.max_lanes_per_track == nil then
        return false, "missing required key: 'max_lanes_per_track'"
    end
    if type(config.max_lanes_per_track) ~= "number" then
        return false, "'max_lanes_per_track' must be a number"
    end
    if config.max_lanes_per_track < 1 and config.max_lanes_per_track ~= 0 then
        return false, "'max_lanes_per_track' must be >= 1, or 0 for unlimited"
    end
    if config.max_lanes_per_track ~= math.floor(config.max_lanes_per_track) then
        return false, "'max_lanes_per_track' must be an integer"
    end
    -- categories is optional, but if present must be an object
    if config.categories ~= nil then
        if type(config.categories) ~= "table" then
            return false, "'categories' must be an object"
        end
        -- Validate each category entry
        for cat_name, cat_config in pairs(config.categories) do
            if type(cat_config) ~= "table" then
                return false, string.format("category '%s' must be an object", cat_name)
            end
            if cat_config.overflow_behavior ~= nil then
                if cat_config.overflow_behavior ~= "lanes" and cat_config.overflow_behavior ~= "new_track" then
                    return false, string.format(
                        "category '%s'.overflow_behavior must be \"lanes\" or \"new_track\"",
                        cat_name
                    )
                end
            end
        end
    end
    return true, nil
end

--- Merge missing keys from defaults into the parsed config.
-- This ensures the config always has every expected key.
-- @param config table - parsed configuration
-- @return table with all default keys populated
function R.Config._merge_defaults(config)
    local defaults = R.Config._defaults()
    local merged = {}
    for k, v in pairs(defaults) do
        if config[k] ~= nil then
            merged[k] = config[k]
        else
            merged[k] = v
        end
    end
    -- categories defaults to {} if missing
    if merged.categories == nil then
        merged.categories = {}
    end
    return merged
end

--- Load route_map.json, parse, validate, and return configuration.
-- Falls back to built-in defaults on any error.
-- Stores the result internally for get_overflow() calls.
-- @param path (optional string) full path to route_map.json.
--             Defaults to same directory as the script.
-- @return table with all config keys populated
function R.Config.load(path)
    path = path or (_script_dir .. "route_map.json")

    local file, open_err = io.open(path, "r")
    if not file then
        reaper.ShowConsoleMsg(
            "Grove: " .. path .. " not found (" .. tostring(open_err) .. "). "
                .. "Using built-in defaults.\n"
        )
        local cfg = R.Config._defaults()
        R.Config._data = cfg
        return cfg
    end

    local content = file:read("*a")
    file:close()

    if #content == 0 then
        reaper.ShowConsoleMsg(
            "Grove: " .. path .. " is empty. Using built-in defaults.\n"
        )
        local cfg = R.Config._defaults()
        R.Config._data = cfg
        return cfg
    end

    local config, parse_err = R.parse_json(content)
    if not config then
        reaper.ShowConsoleMsg(
            "Grove: JSON parse error in " .. path .. ": " .. parse_err
                .. ". Using built-in defaults.\n"
        )
        local cfg = R.Config._defaults()
        R.Config._data = cfg
        return cfg
    end

    local valid, val_err = R.Config._validate(config)
    if not valid then
        reaper.ShowConsoleMsg(
            "Grove: Schema validation error in " .. path .. ": " .. val_err
                .. ". Using built-in defaults.\n"
        )
        local cfg = R.Config._defaults()
        R.Config._data = cfg
        return cfg
    end

    local cfg = R.Config._merge_defaults(config)
    R.Config._data = cfg
    return cfg
end

--- Resolve overflow behavior for a given category.
-- Checks per-category override first, then falls back to global setting.
-- Requires load() to have been called first.
-- @param category string - canonical category name
-- @return string "lanes" or "new_track", or nil if config not loaded
function R.Config.get_overflow(category)
    local config = R.Config._data
    if not config then
        reaper.ShowConsoleMsg("Grove: Config not loaded. Call R.Config.load() first.\n")
        return nil
    end
    -- Per-category override
    if config.categories and config.categories[category] then
        local cat_behavior = config.categories[category].overflow_behavior
        if cat_behavior ~= nil then
            return cat_behavior
        end
    end
    -- Global fallback
    return config.overflow_behavior
end


-- ════════════════════════════════════════════════════════════════════════
-- MODULE PLACEHOLDERS (future phases)
-- ════════════════════════════════════════════════════════════════════════

-- Phase 2: Calibration System
-- R.Calibration = {}

-- Phase 3: Matching Engine
-- R.Import = {}

-- Phase 4: Overflow Dispatch
-- R.Overflow = {}


-- ════════════════════════════════════════════════════════════════════════
-- ENTRY POINT
-- ════════════════════════════════════════════════════════════════════════

-- Load configuration at startup for instant feedback.
-- Full pipeline (scan, match, insert, overflow) will be wired in later phases.
local config = R.Config.load()
if config then
    local alias_count = 0
    for _ in pairs(config.alias) do
        alias_count = alias_count + 1
    end
    local cat_count = 0
    for _ in pairs(config.categories) do
        cat_count = cat_count + 1
    end
    local verdict = R.Config.get_overflow("sub_bass")
    reaper.ShowConsoleMsg("Grove Stem Auto-Router loaded.\n")
    reaper.ShowConsoleMsg(
        string.format(
            "  Config: overflow=%s, max_lanes=%d, aliases=%d, categories=%d, ignore_keywords=%d\n"
                .. "  sub_bass overflow: %s (per-category override)\n",
            config.overflow_behavior,
            config.max_lanes_per_track,
            alias_count,
            cat_count,
            #(config.keywords_ignore or {}),
            verdict or "nil"
        )
    )
end

-- Export R globally for REAPER console debugging
_G.R = R
