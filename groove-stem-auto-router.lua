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
    if type(str) ~= "string" then
        return nil, "expected string, got " .. type(str)
    end
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
-- CALIBRATION MODULE (Phase 2)
-- ════════════════════════════════════════════════════════════════════════

R.Calibration = {}

--- Load GUIDs from project ExtState.
-- Reads SetProjExtState("GROVE_STEMS", "TargetGUIDs") and parses as JSON array.
-- @return table { guid_string = true, ... } or nil if none stored
function R.Calibration.load()
    -- GetProjExtState returns (boolean retval, string value) in some REAPER
    -- versions and just (string) in others. Wrap in a helper to capture all returns.
    local function _get_ext_state()
        return reaper.GetProjExtState(0, "GROVE_STEMS", "TargetGUIDs")
    end
    local ok, ret1, ret2 = pcall(_get_ext_state)
    if not ok then
        return nil
    end
    -- ret1 is either the boolean retval (two-return API) or the value string (one-return)
    local json_str
    if type(ret1) == "boolean" then
        json_str = ret2  -- two-return API: ret2 is the actual value
    else
        json_str = ret1  -- one-return API: ret1 is the value
    end
    if type(json_str) ~= "string" or json_str == "" then
        return nil
    end
    local guids, err = R.parse_json(json_str)
    if not guids or type(guids) ~= "table" then
        reaper.ShowConsoleMsg("Grove: Invalid calibration data in ExtState: " .. tostring(err) .. "\n")
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

--- Validate stored GUIDs against current REAPER project tracks.
-- Wraps BR_GetMediaTrackByGUID in pcall for SWS-optional safety.
-- @param guid_map table - { guid_string = true, ... } from load()
-- @return (valid_map, stale_list)
--   valid_map: { guid_string = REAPER_track, ... }
--   stale_list: { guid_string, ... }
function R.Calibration.validate(guid_map)
    local valid = {}
    local stale = {}
    for guid in pairs(guid_map) do
        local ok, track = pcall(reaper.BR_GetMediaTrackByGUID, 0, guid)
        if ok and track then
            local ret, name = pcall(reaper.GetTrackName, track, "")
            if ret then
                valid[guid] = track
            else
                stale[#stale + 1] = guid
            end
        else
            stale[#stale + 1] = guid
        end
    end
    if #stale > 0 then
        reaper.ShowConsoleMsg("Grove: " .. #stale .. " stale calibration GUID(s) found. Falling back to name match for those.\n")
    end
    return valid, stale
end

--- Save selected track GUIDs to project ExtState as a JSON array.
-- @param tracks array of REAPER track objects
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
        return
    end
    local json = "[" .. table.concat(parts, ",") .. "]"
    reaper.SetProjExtState(0, "GROVE_STEMS", "TargetGUIDs", json)
    reaper.ShowConsoleMsg("Grove: Calibration saved " .. #parts .. " track GUID(s).\n")
end

-- ════════════════════════════════════════════════════════════════════════
-- IMPORT / MATCHING MODULE (Phase 3)
-- ════════════════════════════════════════════════════════════════════════

R.Import = {}

--- Scan a directory for stem audio files (.wav, .flac, .mp3).
-- Paths normalized to forward slashes.
-- @param dir string - directory path
-- @return array of { path = string, name = string }
function R.Import.scan(dir)
    dir = dir:gsub("\\", "/")
    if dir:sub(-1) ~= "/" then
        dir = dir .. "/"
    end
    local stems = {}
    local i = 0
    while true do
        local filename = reaper.EnumerateFiles(dir, i)
        if filename == "" then break end
        local ext = filename:lower():match("%.([^%.]+)$")
        if ext == "wav" or ext == "flac" or ext == "mp3" then
            stems[#stems + 1] = {
                path = dir .. filename:gsub("\\", "/"),
                name = filename
            }
        end
        i = i + 1
    end
    return stems
end

--- Normalize a stem filename to a canonical category name.
-- Strips keywords_ignore tokens, applies alias substitution,
-- falls back to the first remaining token.
-- @param name string - original filename
-- @param config table - merged route_map config
-- @return string - canonical category name
function R.Import.normalize(name, config)
    -- Strip extension, normalize separators, lowercase
    local base = name:gsub("%.[^%.]+$", "")
    local cleaned = base:gsub("[_%-%.]", " "):lower()
    -- Tokenize
    local tokens = {}
    for token in cleaned:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end
    -- Build ignore set
    local ignore = {}
    for _, kw in ipairs(config.keywords_ignore or {}) do
        ignore[kw:lower()] = true
    end
    -- Filter out ignored keywords
    local filtered = {}
    for _, token in ipairs(tokens) do
        if not ignore[token] then
            filtered[#filtered + 1] = token
        end
    end
    -- Build alias lookup (lowered key -> canonical category)
    local alias_map = {}
    for alias_key, cat in pairs(config.alias or {}) do
        alias_map[alias_key:lower()] = cat
    end
    -- Check each remaining token against alias keys
    for _, token in ipairs(filtered) do
        local mapped = alias_map[token]
        if mapped then
            return mapped
        end
    end
    -- No alias match: first remaining token is the category
    if #filtered > 0 then
        return filtered[1]
    end
    return base:lower()
end

--- Match a canonical category to a REAPER track.
-- Case-insensitive name match first, GUID override on collision
-- when calibration data is available.
-- @param category string - canonical category name
-- @param tracks array of { track = MediaTrack, name = string }
-- @param guid_map table - { guid_string = MediaTrack, ... } from validate(), or nil
-- @return (MediaTrack | nil, matched_name | nil)
function R.Import.match(category, tracks, guid_map)
    local cat_lower = category:lower()
    local matches = {}
    for _, t in ipairs(tracks) do
        local tname = (t.name or ""):lower()
        if tname == cat_lower then
            matches[#matches + 1] = t
        end
    end
    if #matches == 0 then
        return nil, nil
    end
    if #matches == 1 then
        return matches[1].track, matches[1].name
    end
    -- Collision: try GUID disambiguation
    if guid_map then
        for _, t in ipairs(matches) do
            local ok, guid = pcall(reaper.GetTrackGUID, t.track)
            if ok and guid and guid_map[guid] then
                return t.track, t.name
            end
        end
    end
    -- No GUID or no match: first match wins, overflow handles surplus
    return matches[1].track, matches[1].name
end

--- Insert a media file on a track at position 0.0.
-- Internal helper used by main pipeline and overflow.
-- @param path string - normalized file path
-- @param track MediaTrack - destination track
-- @return MediaItem or nil
function R.Import._insert_media(path, track)
    local item = reaper.AddMediaItemToTrack(track)
    if not item then
        reaper.ShowConsoleMsg("Grove: Failed to create media item for " .. path .. "\n")
        return nil
    end
    reaper.GetSetMediaItemInfo(item, "D_POSITION", 0.0)
    local take = reaper.AddTakeToMediaItem(item)
    if not take then
        reaper.ShowConsoleMsg("Grove: Failed to create take for " .. path .. "\n")
        return item
    end
    local basename = path:match("([^/]+)%.[^%.]+$") or path
    reaper.GetSetMediaItemTakeInfo(take, "P_NAME", basename)
    local src = reaper.PCM_Source_CreateFromFile(path)
    if src then
        reaper.GetSetMediaItemTakeInfo(take, "P_SOURCE", src)
        local len = reaper.GetMediaSourceLength(src)
        if len then
            reaper.GetSetMediaItemInfo(item, "D_LENGTH", len)
        end
    end
    reaper.UpdateItemInProject(item)
    return item
end

-- ════════════════════════════════════════════════════════════════════════
-- OVERFLOW DISPATCH MODULE (Phase 4)
-- ════════════════════════════════════════════════════════════════════════

R.Overflow = {}

-- Cached availability of the Fixed Lanes API
R.Overflow._has_fixed_lanes = nil

--- Check if SetTrackLaneComping (REAPER 6.0+) is available.
-- Uses APIExists if available, falls back to pcall.
-- @return boolean
function R.Overflow._check_lanes_api()
    if R.Overflow._has_fixed_lanes ~= nil then
        return R.Overflow._has_fixed_lanes
    end
    if reaper.APIExists then
        R.Overflow._has_fixed_lanes = reaper.APIExists("SetTrackLaneComping")
    else
        -- Fallback for older REAPER: try call with first track
        local t = reaper.GetTrack(0, 0)
        if t then
            local ok = pcall(reaper.SetTrackLaneComping, t, 0)
            R.Overflow._has_fixed_lanes = ok
        else
            R.Overflow._has_fixed_lanes = false
        end
    end
    if not R.Overflow._has_fixed_lanes then
        reaper.ShowConsoleMsg("Grove: Fixed Lanes API unavailable (REAPER < 6.0?). Falling back to new track creation.\n")
    end
    return R.Overflow._has_fixed_lanes
end

--- Dispatch a surplus stem to a lane or new track per config.
-- @param stem table - { path = string, name = string }
-- @param track MediaTrack - the matched category track
-- @param config table - merged route_map config
-- @param idx number - surplus index
function R.Overflow.dispatch(stem, track, config, idx)
    local category = R.Import.normalize(stem.name, config)
    local behavior = R.Config.get_overflow(category)
    -- Count existing media items on the track
    local item_count = 0
    while reaper.GetTrackMediaItem(track, item_count) do
        item_count = item_count + 1
    end
    if behavior == "lanes" and R.Overflow._check_lanes_api() then
        local max_lanes = config.max_lanes_per_track or 0
        if max_lanes == 0 or item_count < max_lanes then
            R.Overflow._to_lane(stem, track)
        else
            local stem_name = stem.name:gsub("%.[^%.]+$", "")
            reaper.ShowConsoleMsg("Grove: Lane cap (" .. max_lanes .. ") reached. Creating new track for '" .. stem_name .. "'.\n")
            R.Overflow._to_new_track(stem, track)
        end
    else
        R.Overflow._to_new_track(stem, track)
    end
end

--- Insert surplus stem as a new lane on the existing track.
-- Enables fixed lane mode via SetTrackLaneComping (no-op if already set).
-- @param stem table - { path = string, name = string }
-- @param track MediaTrack
function R.Overflow._to_lane(stem, track)
    reaper.SetTrackLaneComping(track, 0)
    R.Import._insert_media(stem.path, track)
end

--- Create a new track below the category track and insert surplus stem.
-- Sets I_FOLDERDEPTH to 0 (normal track inside any parent folder).
-- @param stem table - { path = string, name = string }
-- @param category_track MediaTrack - the matched category track
function R.Overflow._to_new_track(stem, category_track)
    local track_idx = -1
    for i = 0, reaper.CountTracks(0) - 1 do
        if reaper.GetTrack(0, i) == category_track then
            track_idx = i
            break
        end
    end
    reaper.InsertTrackAtIndex(track_idx + 1, true)
    local new_track = reaper.GetTrack(0, track_idx + 1)
    reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 0)
    local ret, orig_name = reaper.GetTrackName(category_track, "")
    local stem_name = stem.name:gsub("%.[^%.]+$", "")
    reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", orig_name .. " - " .. stem_name, true)
    R.Import._insert_media(stem.path, new_track)
end

-- ════════════════════════════════════════════════════════════════════════
-- ENTRY POINT
-- ════════════════════════════════════════════════════════════════════════

-- Detect calibration mode from command args
-- GetCommandArgs was added in REAPER 6.73+; guard it for older versions
local _is_calibrate = false
local _get_cmd = reaper.GetCommandArgs
if _get_cmd then
    local _cmd_args = _get_cmd()
    if _cmd_args then
        for _, _arg in ipairs(_cmd_args) do
            if _arg == "--calibrate" then
                _is_calibrate = true
                break
            end
        end
    end
end

if _is_calibrate then
    -- Calibration mode: user selects tracks, GUIDs persisted
    reaper.ShowConsoleMsg("Grove: Calibration mode — select tracks to calibrate, then click OK.\n")
    reaper.ShowMessageBox("Select the tracks to calibrate, then click OK.", "Grove Calibration", 0)
    local _selected = {}
    for _i = 0, reaper.CountSelectedTracks(0) - 1 do
        _selected[#_selected + 1] = reaper.GetSelectedTrack(0, _i)
    end
    if #_selected == 0 then
        reaper.ShowConsoleMsg("Grove: No tracks selected. Calibration cancelled.\n")
        return
    end
    R.Calibration.save(_selected)
    return
end

-- Normal pipeline: load config, scan stems, match, insert, overflow
local config = R.Config.load()
if not config then
    reaper.ShowConsoleMsg("Grove: Config loading failed. Aborting.\n")
    return
end

-- Load and validate calibration data (optional, graceful fallback)
local guid_map = nil
local raw_guids = R.Calibration.load()
if raw_guids then
    local valid, stale = R.Calibration.validate(raw_guids)
    if next(valid) then
        guid_map = valid
    end
end

-- Collect REAPER tracks: { track, name } pairs
local reaper_tracks = {}
for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local ret, tr_name = reaper.GetTrackName(tr, "")
    reaper_tracks[#reaper_tracks + 1] = { track = tr, name = tr_name }
end

-- Scan stem directory (same directory as the script)
local stems = R.Import.scan(_script_dir)

if #stems == 0 then
    reaper.ShowConsoleMsg("Grove: No audio files found in '" .. _script_dir .. "'\n")
    return
end

-- Main pipeline: insert stems, handle overflow
reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

local used_tracks = {}
local insert_count = 0
local overflow_count = 0
local skip_count = 0

for _, stem in ipairs(stems) do
    local category = R.Import.normalize(stem.name, config)
    local matched, matched_name = R.Import.match(category, reaper_tracks, guid_map)
    if matched then
        local track_key = tostring(matched)
        if not used_tracks[track_key] then
            -- First stem for this track: direct insert
            R.Import._insert_media(stem.path, matched)
            used_tracks[track_key] = true
            insert_count = insert_count + 1
        else
            -- Surplus stem: overflow dispatch
            R.Overflow.dispatch(stem, matched, config, overflow_count)
            overflow_count = overflow_count + 1
        end
    else
        reaper.ShowConsoleMsg("Grove: No track match for '" .. stem.name .. "' (category: " .. category .. ")\n")
        skip_count = skip_count + 1
    end
end

reaper.Undo_EndBlock("Grove Stem Auto-Router", -1)
reaper.PreventUIRefresh(-1)

reaper.ShowConsoleMsg(string.format(
    "Grove: %d stem(s) found. %d inserted, %d overflowed, %d skipped. Run complete.\n",
    #stems, insert_count, overflow_count, skip_count
))

-- Export R globally for REAPER console debugging
_G.R = R
