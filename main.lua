--[[
    Grove Stem Auto-Router v2
    ========================
    Automatically route FL Studio stem exports to REAPER tracks.
    
    Architecture:
      main.lua              ← Entry point — register this in REAPER Actions
      lib/json.lua           Inline JSON parser (zero deps)
      lib/config.lua         route_map.json loader + validation
      lib/calibration.lua    GUID-based track calibration
      lib/import.lua         File scanner, name normalizer, matcher, media inserter
      lib/overflow.lua       Overflow dispatch (lanes / new track)
      gui/main_window.lua    ReaImGui interface
      route_map.json         User-editable alias / ignore / overflow config
    
    Dependencies:
      REAPER 6.0+
      ReaImGui (via ReaPack)
      SWS Extension (optional, for BR_GetMediaTrackByGUID)
    
    Usage:
      Place the entire folder in REAPER's Scripts directory.
      Register main.lua in Actions → ReaScript → Load.
      Run the action.
--]]

-- ══════════════════════════════════════════════════════════════════════
-- 0. Error wrapper — anything that fails shows in REAPER console
-- ══════════════════════════════════════════════════════════════════════

local ok_init, init_err = pcall(function()

-- ══════════════════════════════════════════════════════════════════════
-- 1. Discover script directory (needed by all modules)
-- ══════════════════════════════════════════════════════════════════════

local src = debug.getinfo(1, "S").source or ""
if src:sub(1, 1) == "@" then src = src:sub(2) end
src = src:gsub("\\", "/")
local script_dir = src:match("^(.*/)") or ""

-- ══════════════════════════════════════════════════════════════════════
-- 2. Shared namespace table
-- ══════════════════════════════════════════════════════════════════════

local R = {
    _script_dir = script_dir,
}

-- ══════════════════════════════════════════════════════════════════════
-- 3. Load modules in dependency order
-- ══════════════════════════════════════════════════════════════════════

-- json has no deps
local JSON = dofile(script_dir .. "lib/json.lua")

-- config depends on json
dofile(script_dir .. "lib/config.lua")(R, JSON)

-- calibration depends on json
dofile(script_dir .. "lib/calibration.lua")(R, JSON)

-- import depends on R.Config (via get_alias_map / get_ignore_set)
dofile(script_dir .. "lib/import.lua")(R)

-- overflow depends on R.Config + R.Import
dofile(script_dir .. "lib/overflow.lua")(R)

-- ══════════════════════════════════════════════════════════════════════
-- 4. Launch GUI
-- ══════════════════════════════════════════════════════════════════════

local gui = dofile(script_dir .. "gui/main_window.lua")
gui.launch(R)

end) -- pcall

if not ok_init then
    reaper.ShowConsoleMsg("GROVE STEM AUTO-ROUTER ERROR:\n" .. tostring(init_err) .. "\n")
    reaper.ShowMessageBox(
        "Grove Stem Auto-Router failed to initialize.\n\nError:\n" .. tostring(init_err)
            .. "\n\nCheck View → Console for details.",
        "Grove Error", 0
    )
end
