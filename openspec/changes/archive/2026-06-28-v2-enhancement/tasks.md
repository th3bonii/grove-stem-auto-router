# Tasks: V2 Enhancement — Matching Engine & Architecture Overhaul

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 550–650 |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (Config) → PR 2 (Match) → PR 3 (Orphan/Overflow) → PR 4 (Polish) → PR 5 (AI) |
| Delivery strategy | auto-forecast |
| Chain strategy | stacked-to-main |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Base |
|------|------|------|
| 1 | Config + route_map v2 schema | main |
| 2 | Matching engine + fuzzy + calibration | main |
| 3 | Orphan + overflow + color + undo | main |
| 4 | Template manifest | main |
| 5 | AI Hybrid Layer (Python server) | main |

## Phase 1: Foundation — Config & Schema

- [x] 1.1 Restructure `route_map.json` v2: add `fuzzy_threshold`, `alias_priority`, `lanes_mode`, `color_stems_by_track`, `ai_config`
- [x] 1.2 Update `lib/config.lua`: new schema fields with defaults, validation, getters
- [x] 1.3 Wire new module stubs into `main.lua` require chain

## Phase 2: Matching Engine

- [x] 2.1 Create `lib/matching-engine.lua`: `tokenize()`, `_token_interscore(a, b)` = shared/min(a,b), priority chain GUID→token→fuzzy→exact
- [x] 2.2 Create `lib/fuzzy.lua`: pure-function Levenshtein distance, token-pair iteration, threshold comparator
- [x] 2.3 Modify `lib/calibration.lua`: `get_track_map()` returns `{guid → track}` for matching-engine primary use
- [x] 2.4 Modify `lib/import.lua`: delegate matching to engine (`match_stem()`); pass category context to overflow; store display name via `stem.display_name`
- [x] 2.5 Wire matching pipeline into `gui/main_window.lua` `run_matching()` with calibrator's `get_track_map()`

## Phase 3: Orphan Handling & Overflow

- [x] 3.1 Create `lib/orphan.lua`: collect unmatched stems, GUI data model, auto-create tracks from orphans
- [x] 3.2 Modify `gui/main_window.lua`: orphans table (filename, category, reason) with multi-select and Insert
- [x] 3.3 Modify `lib/overflow.lua` `_to_new_track()`: walk `I_FOLDERDEPTH` chain upward, create inside parent folder
- [x] 3.4 Add REAPER 7 Fixed Lanes detection: `SetMediaTrackLanes` vs fallback `SetTrackLaneComping`
- [x] 3.5 Pass category context from match to overflow `dispatch()` — no filename re-parse
- [x] 3.6 Color inheritance in `insert_media()`: read `I_CUSTOMCOLOR` from track, apply to item

## Phase 4: Polish & Manifest

- [x] 4.1 Fix undo flag: change `-1` → `0` in `Undo_EndBlock` in `gui/main_window.lua`
- [x] 4.2 Template manifest: preflight scan (name, index, GUID, depth, calibration), show in ReaImGui table

## Phase 5: AI Hybrid Layer

- [x] 5.1 Create `ai-proxy/main.py`: reads `orphans.json`, LLM prompt with music-production synonyms, writes `mapping.json`
- [x] 5.2 Create `ai-proxy/requirements.txt`: `openai`, `python-dotenv`
- [x] 5.3 Create `ai-proxy/.env.example`: template for `OPENAI_API_KEY`
- [x] 5.4 Lua: export orphans as JSON after matching, poll for `mapping.json`, apply AI matches
- [x] 5.5 GUI: AI panel with API key field, enable toggle, status indicator
