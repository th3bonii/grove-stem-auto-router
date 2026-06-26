-- Grove Stem Auto-Router / lib/config.lua
-- route_map.json loader with schema validation and default merging
-- Depends on: JSON (from lib/json.lua)

return function(R, JSON)
    R.Config = {}

    R.Config._data = nil

    function R.Config._defaults()
        return {
            alias = {},
            keywords_ignore = {},
            overflow_behavior = "lanes",
            max_lanes_per_track = 6,
            categories = {}
        }
    end

    function R.Config._validate(config)
        if type(config) ~= "table" then return false, "root must be an object" end
        if config.alias == nil then return false, "missing 'alias'" end
        if type(config.alias) ~= "table" then return false, "'alias' must be an object" end
        if config.keywords_ignore == nil then return false, "missing 'keywords_ignore'" end
        if type(config.keywords_ignore) ~= "table" then return false, "'keywords_ignore' must be an array" end
        if config.overflow_behavior == nil then return false, "missing 'overflow_behavior'" end
        if config.overflow_behavior ~= "lanes" and config.overflow_behavior ~= "new_track" then
            return false, "'overflow_behavior' must be \"lanes\" or \"new_track\""
        end
        if config.max_lanes_per_track == nil then return false, "missing 'max_lanes_per_track'" end
        if type(config.max_lanes_per_track) ~= "number" then return false, "'max_lanes_per_track' must be a number" end
        if config.max_lanes_per_track < 1 and config.max_lanes_per_track ~= 0 then
            return false, "'max_lanes_per_track' must be >= 1 or 0 for unlimited"
        end
        config.max_lanes_per_track = math.floor(config.max_lanes_per_track)
        if config.categories ~= nil then
            if type(config.categories) ~= "table" then return false, "'categories' must be an object" end
            for cat_name, cat_cfg in pairs(config.categories) do
                if type(cat_cfg) ~= "table" then return false, "category '" .. cat_name .. "' must be an object" end
                if cat_cfg.overflow_behavior ~= nil and cat_cfg.overflow_behavior ~= "lanes" and cat_cfg.overflow_behavior ~= "new_track" then
                    return false, "category '" .. cat_name .. "'.overflow_behavior must be \"lanes\" or \"new_track\""
                end
            end
        end
        return true, nil
    end

    function R.Config._merge_defaults(config)
        local defaults = R.Config._defaults()
        local merged = {}
        for k, v in pairs(defaults) do
            merged[k] = config[k] ~= nil and config[k] or v
        end
        if merged.categories == nil then merged.categories = {} end
        return merged
    end

    function R.Config.load(path)
        path = path or (R._script_dir .. "route_map.json")
        local file, open_err = io.open(path, "r")
        if not file then
            reaper.ShowConsoleMsg("Grove: " .. path .. " not found. Using built-in defaults.\n")
            local cfg = R.Config._defaults(); R.Config._data = cfg; return cfg
        end
        local content = file:read("*a"); file:close()
        if #content == 0 then
            reaper.ShowConsoleMsg("Grove: " .. path .. " is empty. Using built-in defaults.\n")
            local cfg = R.Config._defaults(); R.Config._data = cfg; return cfg
        end
        local config, parse_err = JSON.parse(content)
        if not config then
            reaper.ShowConsoleMsg("Grove: JSON error in " .. path .. ": " .. tostring(parse_err) .. ". Using defaults.\n")
            local cfg = R.Config._defaults(); R.Config._data = cfg; return cfg
        end
        local valid, val_err = R.Config._validate(config)
        if not valid then
            reaper.ShowConsoleMsg("Grove: Schema error in " .. path .. ": " .. tostring(val_err) .. ". Using defaults.\n")
            local cfg = R.Config._defaults(); R.Config._data = cfg; return cfg
        end
        local cfg = R.Config._merge_defaults(config)
        R.Config._data = cfg
        return cfg
    end

    function R.Config.get_overflow(category)
        local config = R.Config._data
        if not config then
            reaper.ShowConsoleMsg("Grove: Config not loaded. Call R.Config.load() first.\n")
            return "lanes"  -- safe fallback
        end
        if config.categories and config.categories[category] then
            local cat_behavior = config.categories[category].overflow_behavior
            if cat_behavior ~= nil then return cat_behavior end
        end
        return config.overflow_behavior
    end

    function R.Config.get_alias_map()
        local config = R.Config._data
        if not config then return {} end
        local map = {}
        for k, v in pairs(config.alias or {}) do
            map[k:lower()] = v
        end
        return map
    end

    function R.Config.get_ignore_set()
        local config = R.Config._data
        if not config then return {} end
        local set = {}
        for _, kw in ipairs(config.keywords_ignore or {}) do
            set[kw:lower()] = true
        end
        return set
    end
end
