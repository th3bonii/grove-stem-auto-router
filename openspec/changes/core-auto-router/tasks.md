# Tasks: Core Auto-Router

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~490 |
| 400-line budget risk | Medium |
| Chained PRs recommended | Yes |
| Suggested split | PR 1: JSON parser + config. PR 2: calibration + matching + overflow + main pipeline |
| Delivery strategy | auto-forecast |
| Chain strategy | feature-branch-chain |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | JSON parser + config loader + `route_map.json` (foundation, ~130 lines) | PR 1 | Independent, no REAPER project state needed |
| 2 | Calibration + matching + overflow + main pipeline (~360 lines) | PR 2 | Depends on PR 1's config loader. Base = main |

## Phase 1: JSON Parser & Config

- [x] 1.1 Create `route_map.json` with `alias`, `keywords_ignore`, `overflow_behavior`, `max_lanes_per_track`, `categories`
- [x] 1.2 Write `R.parse_json(str)` — recursive-descent parser: objects, arrays, strings, numbers, booleans, null
- [x] 1.3 Write `R.Config.load(path)` — parse `route_map.json`, validate schema, merge defaults on missing
- [x] 1.4 Write `R.Config.get_overflow(category)` — per-category override or global fallback

## Phase 2: Calibration System

- [x] 2.1 Write `R.Calibration.load()` — read GUIDs via `SetProjExtState("GROVE_STEMS", "TargetGUIDs")`
- [x] 2.2 Write `R.Calibration.validate(guid_map)` — verify GUIDs with `BR_GetMediaTrackByGUID`, return stale list
- [x] 2.3 Write `R.Calibration.save(tracks)` — serialize GUIDs to ExtState as JSON array
- [x] 2.4 Handle `--calibrate` flag: prompt track selection, call save, exit cleanly

## Phase 3: Matching Engine

- [x] 3.1 Write `R.Import.scan(dir)` — collect `.wav`/`.flac`/`.mp3`, normalize paths to forward slashes
- [x] 3.2 Write `R.Import.normalize(name, config)` — strip `keywords_ignore`, apply alias substitution, extract category
- [x] 3.3 Write `R.Import.match(category, tracks, guid_map)` — name match first, GUID override on collision
- [x] 3.4 Write media insertion — `InsertMedia` at position 0.0 on matched track, path normalized

## Phase 4: Overflow & Main Pipeline

- [x] 4.1 Write runtime API detection — check `SetTrackLaneComping` availability, set fallback flag
- [x] 4.2 Write `R.Overflow.dispatch(stem, track, config, idx)` — lane or new_track per config
- [x] 4.3 Write lane logic — `SetTrackLaneComping`, cap at `max_lanes_per_track`, fallback to new_track
- [x] 4.4 Write new_track logic — `InsertTrack` below last category track, copy `I_FOLDERDEPTH`
- [x] 4.5 Write main entry — parse args, run pipeline, wrap in `Undo_BeginBlock`/`EndBlock`/`PreventUIRefresh`
