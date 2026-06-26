# Design: Core Auto-Router

## Technical Approach

Single Lua script with an internal module table (`R = {Config, Import, Calibration, Overflow}`) driving a linear pipeline: scan folder → normalize filenames → match to tracks (name-first, GUID override on collision) → insert items → overflow surplus. `route_map.json` loaded side-by-side at each run with an inline JSON parser. Atomic undo block wraps all insertions.

## Architecture Decisions

### Module Organization

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Flat functions, no namespacing | Simple but collisions as script grows | Rejected |
| Internal module table (`R.*`) | Clear subsystem isolation, single `.lua`, Lua idiom | **Chosen** |
| Multi-file with `require()` | Violates single-file constraint, REAPER path issues | Rejected |

### Matching Priority

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Name-only | Simple; collisions require manual ordering | Rejected |
| GUID-first | Forces calibration on all users | Rejected |
| Name-first with GUID override on collision | Works out of box, calibration optional for disambiguation | **Chosen** |

### Overflow Dispatch

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Always lanes | Simple, but REAPER < 6.0 lacks Fixed Lanes API | Rejected |
| Always new tracks | Works everywhere; wastes lane capability | Rejected |
| Config-driven with per-category override + API detection | Flexible per session; fallback if API unavailable | **Chosen** |

### Inline JSON Parser

| Option | Tradeoff | Decision |
|--------|----------|----------|
| `dkjson` bundled | Battle-tested, but extra weight | Rejected |
| Minimal hand-written recursive-descent parser | ~80 lines, covers all required types, zero deps | **Chosen** |

## Data Flow

```
route_map.json ──→ R.Config.load() ──→ normalized rules
                       │
stem folder ──→ scan .wav/.flac/.mp3 ──→ normalize per alias + keywords_ignore
                                              │
                                              ▼
                                     name-match to REAPER tracks
                                              │
                                   ┌──────────┼──────────┐
                                   ▼          ▼          ▼
                               match OK   collision   no match
                                   │          │          │
                                   │    calibr. GUID    warn + skip
                                   │    disambiguates   │
                                   ▼          ▼          │
                              insert at pos 0.0 ◄────────┘
                                   │
                                   ▼
                           overflow? ──no──→ done
                               │ yes
                               ▼
                    ┌──── config.decision ────┐
                    ▼                          ▼
               lanes mode                new_track mode
               │                         │
               ▼                         ▼
        SetTrackLaneComping        InsertTrack + set I_FOLDERDEPTH
        cap max_lanes_per_track    below last category track
        fallback → new_track if    │
        API unavailable            │
                                   ▼
                            done (single undo block)
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `groove-stem-auto-router.lua` | Create | Main script: all 4 subsystems + inline JSON parser + entry point |
| `route_map.json` | Create | User-editable config: alias, keywords_ignore, overflow_behavior, categories |

## Interfaces / Contracts

### Module Table (`R`)

```lua
R.Config = {
  load(path)             → table | nil, err   -- parses route_map.json, validates schema
  get_overflow(category) → "lanes" | "new_track"  -- respects per-category override
}

R.Import = {
  scan(dir)              → {stem_path, stem_name}[]  -- only .wav/.flac/.mp3
  normalize(name, config)→ normalized_category       -- alias subst + ignore strip
  match(category, tracks, guid_map) → reaper_track | nil
}

R.Calibration = {
  load()                 → {guid→track_name} | nil   -- from SetProjExtState
  validate(guid_map)     → valid_map, stale[]        -- check GUIDs exist
  save(tracks)           → nil                       -- serialize via ProjExtState
}

R.Overflow = {
  dispatch(stem, track, config, idx) → nil   -- lanes or new_track per config
}
```

### `route_map.json` Schema

```json
{
  "alias": { "[keyword,...]": "category_name" },
  "keywords_ignore": ["v1", "mix", "loop"],
  "overflow_behavior": "lanes",
  "max_lanes_per_track": 4,
  "categories": {
    "sub_bass": { "overflow_behavior": "new_track" }
  }
}
```

### ExtState GUID Format

```
Key: "GROVE_STEMS" / "TargetGUIDs"
Value: '["A1B2C3...", "D4E5F6..."]'   -- JSON array of hex GUIDs
```

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | Inline JSON parser | Feed valid/invalid JSON strings; verify Lua table output |
| Unit | Name normalization | Alias substitution, ignore-strip, case handling |
| Unit | `route_map` schema validation | Missing keys, wrong types, defaults merging |
| Manual | Full pipeline in REAPER | Load project with tracks, run script, verify insertion + undo |
| Manual | Overflow lanes/new_track | Toggle config, observe behavior |
| Manual | Calibration | Run with `--calibrate`, verify ExtState, stale GUID fallback |

## Migration / Rollout

No migration required. Fresh install: place `groove-stem-auto-router.lua` + `route_map.json` side-by-side in the REAPER Scripts directory.

## Open Questions

- [ ] Exact REAPER API for Fixed Lanes detection — runtime check via `APIExists`?
- [ ] Should `max_lanes_per_track = 0` mean "unlimited" or "no lanes"? Spec says unlimited.
- [ ] Calibration UI: use REAPER native track selection or `BR_GetMouseCursorContext_Track`? Spec says either.
