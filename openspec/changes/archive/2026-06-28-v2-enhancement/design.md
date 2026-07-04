# Design: V2 Enhancement — Matching Engine & Architecture Overhaul

## Technical Approach

Extract matching from `import.lua` into a pipeline: **matching-engine → orphan-collect → insert-with-color → overflow**. GUID calibration becomes primary before token analysis. Token-intersection replaces exact-name equality, with Levenshtein fuzzy as fallback. Overflow: folder-aware + REAPER-version-aware. Python proxy (ai-proxy/) for optional LLM orphan resolution. All under one undo block.

## Architecture Decisions

| Option | Tradeoff | Choice |
|--------|----------|--------|
| Matching inline vs standalone module | Coupling vs testability | **Standalone `lib/matching-engine.lua`** — `import.lua` delegates match calls |
| Token-intersection score = shared/min(a,b) vs weighted TF | Simplicity vs accuracy | **shared/min** — sufficient for stem→track where names are short (1-4 tokens) |
| GUID as primary vs tiebreaker | Correctness vs flexibility | **Primary** — if calibration says "track A", trust it |
| Orphans: auto-insert at import time vs GUI prompt | Speed vs user control | **GUI prompt first** — user may manually assign orphans before import |
| Fuzzy: inline vs separate module | Concision vs separation | **Inline in `matching-engine.lua`** — single-file, < 40 lines |
| Overflow: walk I_FOLDERDEPTH vs assume sibling | Robustness vs simplicity | **Walk I_FOLDERDEPTH** — handles deep nesting |
| AI hybrid: OSC vs JSON file polling | Latency vs simplicity | **JSON file polling** — no port conflicts, no extra deps, degrades trivially |
| Color: per-item `I_CUSTOMCOLOR` vs per-take | Visual consistency | **Per-item** — matches track colors in arrange view |
| route_map.json: v2 schema with strict validation vs lenient | Breakage vs clarity | **Strict with defaults** — missing keys fall back to safe defaults, console warnings |

## Data Flow

```
Stems → scan → normalize → [matching-engine] ─→ matched ─→ insert_media (color)
                   |         |      ↑                    |         |
            route_map.json    |  calibration(GUIDs)     overflow?  orphan GUI
                   |         fuzzy                      |  | no    |
                   ↓         fallback                   v  ↓      auto-create
Config ────────────┴──────────────────────────── lanes / new_track  ↓
                                              ai-proxy → LLM → mapping.json
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `lib/matching-engine.lua` | **Create** | Token intersection + Levenshtein fuzzy. Consumes: normalized stem tokens, track list, guid_map. Returns: match + score or nil. |
| `lib/orphan.lua` | **Create** | Orphan collection table, GUI data model, auto-create tracks from orphans. |
| `lib/fuzzy.lua` | **Create** | Pure-function Levenshtein distance, token-pair iteration, threshold comparator. |
| `ai-proxy/main.py` | **Create** | Python proxy: reads `orphans.json`, calls LLM, writes `mapping.json`. |
| `ai-proxy/requirements.txt` | **Create** | `openai`, `python-dotenv`. |
| `lib/import.lua` | **Modify** | Extract matching into delegation to `matching-engine`. Add color inheritance in `insert_media`. Orphan route instead of silent skip. |
| `lib/overflow.lua` | **Modify** | `_to_new_track` walks I_FOLDERDEPTH for parent. REAPER 7 detection → `SetMediaTrackLanes`. Pass category context (no re-parse). |
| `lib/calibration.lua` | **Modify** | `validate()` returns `{guid → track}` for direct consumption by matching-engine as priority list. |
| `lib/config.lua` | **Modify** | Add `fuzzy_threshold`, `alias_priority`, `lanes_mode`, `ai_config`, `color_stems_by_track` to schema and defaults. |
| `gui/main_window.lua` | **Modify** | Orphan table display (filename, proposed category, failure reason). Preflight/manifest button. Track color display. AI config panel (API key input). |
| `main.lua` | **Modify** | Add `matching-engine`, `orphan`, `fuzzy` to module load chain. |
| `route_map.json` | **Modify** | Add `fuzzy_threshold`, `alias_priority`, `lanes_mode`, `color_stems_by_track`. |

## Interfaces / Contracts

```lua
R.MatchingEngine.find(stem_tokens, stem_display_name, tracks, guid_map, config)
  → { track, name, score } | nil        -- token-intersect → fuzzy fallback
R.MatchingEngine._token_interscore(a, b) → float               -- shared/min(a,b)
R.MatchingEngine._levenshtein(a, b)      → int                 -- edit distance

R.Orphan.collect(stems, assignments)      → void               -- fills R.Orphan.orphans[]
R.Orphan.create_as_tracks(R, ctx)        → void               -- new REAPER tracks
```

```json
// route_map.json v2 schema additions
{
  "fuzzy_threshold": 0.8,
  "alias_priority": "first-match" | "best-match",
  "lanes_mode": "auto" | "free" | "fixed",
  "color_stems_by_track": true,
  "ai_config": {
    "enabled": false,
    "provider": "openai",
    "timeout_seconds": 30
  }
}
```

## Testing Strategy

| Layer | What | How |
|-------|------|-----|
| Unit | Token intersection, Levenshtein, alias resolution | Standalone Lua with hardcoded pairs |
| Integration | Scan→match→insert pipeline | Full run on test REAPER project |
| E2E | Orphan creation, color inheritance | 3 unmatched stems → 3 tracks with correct color |
| Manual | REAPER 6 vs 7 lanes, AI proxy | Verify fallback, start proxy + check mapping |

No automated runner (`tdd: false`). All tests manual via `MANUAL_TESTING.md`.

## Migration / Rollout

Old `route_map.json` loads with defaults for missing v2 keys. GUID promotion is transparent — no data migration. AI proxy off by default. Rollback: revert v2 branch.

## Open Questions

- [ ] `alias_priority="best-match"` performance: O(n*m) vs O(n) — acceptable for >50 tracks?
- [ ] Orphan auto-create: nearest category track's folder or project end?
- [ ] API key: `.env` vs ExtState? Spec says `.env`, GUI suggests ExtState.
