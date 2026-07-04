# Verification Report: core-auto-router

**Change**: core-auto-router
**Version**: N/A (single-pass implementation)
**Mode**: Standard (no test runner available — REAPER Lua)

## Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 17 |
| Tasks complete | 17 |
| Tasks incomplete | 0 |

## Build & Tests Execution

**Build**: ➖ Not available (Lua script — no build step)
**Tests**: ➖ No test runner available (REAPER Lua has no standard testing infrastructure)
**Coverage**: ➖ Not available

## Spec Compliance Matrix

### route-map-config

| Requirement | Scenario | Static Evidence | Result |
|---|---|---|---|
| File Location | Side-by-side found | `debug.getinfo(1).source` path resolution (L26-31), `io.open(path, "r")` (L481) | ✅ COMPLIANT |
| File Location | Missing file | `io.open` returns nil → warning + defaults path (L482-489) | ✅ COMPLIANT |
| Schema | Valid schema loads | `_validate()` checks all 5 required keys (L394-448), `_merge_defaults()` fills missing (L455-470) | ✅ COMPLIANT |
| Schema | Invalid JSON | `R.parse_json()` error → console message + defaults (L504-513) | ✅ COMPLIANT |
| Schema | Missing required key | `_validate()` returns false on nil key → defaults path (L515-523) | ✅ COMPLIANT |
| Runtime Reload | Config changes apply next run | `load()` reads file every call, no persistent cache (L478-529) | ✅ COMPLIANT |
| Inline JSON Parser | All types + trailing commas | Full recursive-descent parser (L45-368), handles objects, arrays, strings, numbers, booleans, null, `\uXXXX` | ✅ COMPLIANT |

### stem-import-engine

| Requirement | Scenario | Static Evidence | Result |
|---|---|---|---|
| Scan Audio Files | Read stem folder | `R.Import.scan()` via `reaper.EnumerateFiles`, filters .wav/.flac/.mp3 (L640-660) | ✅ COMPLIANT |
| Scan Audio Files | Non-audio ignored | Extension filter only passes .wav, .flac, .mp3 (L650-651) | ✅ COMPLIANT |
| Name Normalization | Alias substitution | Strip ext → tokenize → ignore filter → alias lookup → first match returns category (L668-706) | ✅ COMPLIANT |
| Name Normalization | Ignore-only (no alias) | No alias match → returns first remaining token after ignore strip (L702-703) | ✅ COMPLIANT |
| Track Name Matching | Case-insensitive match | Both `category:lower()` and `(t.name or ""):lower()` compared (L718-721) | ✅ COMPLIANT |
| Track Name Matching | No match warning | `#matches == 0` → nil, emitted as console warning (L724-726, L955) | ✅ COMPLIANT |
| GUID Calibration Override | GUID disambiguation | On collision (#matches>1), iterate GUIDs via `GetTrackGUID`, match against guid_map (L730-738) | ✅ COMPLIANT |
| Media Insertion | Position 0.0, single undo block | `D_POSITION = 0.0` (L754), `Undo_BeginBlock`/`EndBlock` (L932, L960), `PreventUIRefresh` (L931, L961) | ✅ COMPLIANT |
| Cross-Platform Paths | Forward slashes | `gsub("\\", "/")` on dir (L641), filename (L653), script source (L30) | ✅ COMPLIANT |

### track-calibration

| Requirement | Scenario | Static Evidence | Result |
|---|---|---|---|
| Track Selection | `--calibrate` flag | `reaper.GetCommandArgs()` parsed for `--calibrate` (L870-879) | ✅ COMPLIANT |
| GUID Persistence | Store GUIDs | Serialize as JSON array via `SetProjExtState` (L613-628) | ✅ COMPLIANT |
| GUID Persistence | Cancel selection | Zero selected → cancel message + early return (L889-892) | ✅ COMPLIANT |
| GUID Validation | Valid GUID | `BR_GetMediaTrackByGUID` in pcall → track resolved (L590-597) | ✅ COMPLIANT |
| GUID Validation | Stale GUID | pcall fails or nil → stale list + console warning (L599-607) | ✅ COMPLIANT |
| Calibration Is Optional | No ExtState → name matching | `load()` returns nil → guid_map stays nil, name matching without warnings (L563-581, L906-912) | ✅ COMPLIANT |
| GUID Storage Format | JSON array of hex strings | Manually built `["guid1","guid2"]`, parsed back via `R.parse_json` (L614-626, L568) | ✅ COMPLIANT |

### overflow-handling

| Requirement | Scenario | Static Evidence | Result |
|---|---|---|---|
| Lanes Mode | Surplus to lanes | `SetTrackLaneComping(track, 0)` + `_insert_media` (L839-842) | ✅ COMPLIANT |
| Lanes Mode | API fallback | `_check_lanes_api()` uses `APIExists` or pcall → falls to `_to_new_track()` (L786-806, L821, L831) | ✅ COMPLIANT |
| New Track Mode | Insert below, FOLDERDEPTH | `InsertTrackAtIndex(track_idx + 1)` (L856), `I_FOLDERDEPTH` = 0 (L858) | ✅ COMPLIANT |
| Max Lanes Cap | Hit lane cap (3 of 6) | Count existing items, compare to max_lanes_per_track, fallback (L817-828) | ✅ COMPLIANT |
| Max Lanes Cap | No cap set (0 = unlimited) | `max_lanes == 0` bypasses cap check (L823) | ✅ COMPLIANT |
| Per-Category Override | Category overrides global | `get_overflow()` checks `categories[category].overflow_behavior` first (L536-551) | ✅ COMPLIANT |
| Folder Depth Integrity | Child track FOLDERDEPTH = 0 | Always `I_FOLDERDEPTH = 0` on new overflow track (L858) | ✅ COMPLIANT |

**Compliance summary**: 25/25 scenarios compliant via static analysis

## Correctness (Static Evidence)

| Requirement | Status | Notes |
|---|---|---|
| route_map.json schema validation | ✅ Implemented | Type checks for all 5 required keys; per-category overflow validated |
| Missing file → defaults | ✅ Implemented | 5 fallback paths: not found, empty, parse error, validation error, success |
| Trailing commas in JSON | ✅ Implemented | Correctly parsed in objects (L271-275) and arrays (L327-329) |
| File scan extension filtering | ✅ Implemented | Case-insensitive extension match via `:lower()` |
| Alias substitution priority | ✅ Implemented | Ignore tokens filtered first, alias checked on remaining |
| GUID stale detection | ✅ Implemented | Returns separate valid + stale arrays, console warning |
| Lane cap enforcement | ✅ Implemented | Per-track item count, correct for sequential insertion |
| Empty folder guard | ✅ Implemented | Early return with message (L925-928) |
| API detection caching | ✅ Implemented | Cache flag avoids redundant checks (L787-789) |
| Atomic undo block | ✅ Implemented | Single `Undo_EndBlock` wraps all operations |

## Coherence (Design)

| Decision | Followed? | Notes |
|---|---|---|
| Internal module table `R.*` | ✅ Yes | `R.Config`, `R.Calibration`, `R.Import`, `R.Overflow`, `R.parse_json` |
| Name-first with GUID override on collision | ✅ Yes | Name compare → GUID tiebreaker on collision (L715-741) |
| Config-driven overflow + API detection | ✅ Yes | `get_overflow()` hierarchy, `_check_lanes_api()` cached |
| Minimal recursive-descent JSON parser | ✅ Yes | ~324 lines, zero deps, all required types + trailing commas + `\uXXXX` |
| JSON array of hex GUIDs in ExtState | ✅ Yes | `["{guid1}","{guid2}"]` via `SetProjExtState` |
| Single undo block for all insertions | ✅ Yes | Blocks wrap the entire insertion loop |
| Forward-slash path normalization | ✅ Yes | Applied to script dir, filenames, scan results |

## Issues Found

**CRITICAL**: None

**WARNING**: None

**SUGGESTION**:
1. **Dead code guard** (line 899): `if not config then` is unreachable — `R.Config.load()` always returns a table (defaults on failure). Consider removing or replacing with a meaningful invariant check.
2. **API detection side effect**: The pcall fallback in `_check_lanes_api()` (line 796) calls `SetTrackLaneComping(t, 0)` on track 0 during detection, which enables fixed lane display. Only triggers in REAPER without `APIExists` (pre-6.0). Low risk but technically mutates project state at startup.
3. **Round-robin vs overflow**: When multiple tracks share the same name and no calibration data exists, only the first matching track gets all surplus stems via overflow; other same-name tracks are unused. Correct per design, but may surprise users who expect distribution across matching tracks.

## Verdict

**PASS** — 17/17 tasks complete, 25/25 spec scenarios compliant via static analysis, all design decisions followed. No critical or blocking issues.
