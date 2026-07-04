# Proposal: Core Auto-Router

## Intent

Automate stem import into REAPER mixing templates. Given a folder of stems, match files to REAPER tracks by name, with intelligent overflow for surplus. No more manual drops.

## Scope

### In Scope
- Offline name-matching engine with `route_map` synonym normalization
- GUID calibration system for disambiguation on name collisions
- Configurable overflow (lanes vs new tracks), hierarchical below matched category
- `route_map.json` with alias groups, ignore patterns, overflow settings
- Inline JSON parser (zero deps)
- Runtime REAPER API detection
- Single-action script with calibration mode

### Out of Scope
- AI/natural language matching (Phase 2 — design defined, build deferred)
- Standalone GUI or REAPER extension beyond a Lua script
- Multi-project batch processing or cross-DAW support

## Capabilities

### New Capabilities
- `stem-import-engine`: Reads stems, normalizes via route_map, matches to tracks, inserts items
- `track-calibration`: User selects tracks, persists GUIDs via `SetProjExtState`
- `route-map-config`: User-editable JSON for synonyms, ignore patterns, overflow behavior, category grouping
- `overflow-handling`: Lane-based and new-track overflow with per-category config

### Modified Capabilities
None — new project, no existing specs.

## Approach

Hybrid: (1) route_map name normalization, (2) GUID calibration on name collision, (3) overflow per config. Overflow tracks created hierarchically below last category track. Single `.lua` + `route_map.json` side-by-side. Bundled JSON parser. Atomic undo block.

## Affected Areas

| Area | Impact |
|------|--------|
| `groove-stem-auto-router.lua` | New |
| `route_map.json` | New |
| `openspec/specs/stem-import-engine/spec.md` | New |
| `openspec/specs/track-calibration/spec.md` | New |
| `openspec/specs/route-map-config/spec.md` | New |
| `openspec/specs/overflow-handling/spec.md` | New |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| JSON parser edge cases (REAPER Lua) | Low | Battle-tested bundled parser |
| REAPER API version differences | Med | Runtime detection + graceful fallback |
| Cross-platform path separator issues | Low | Normalize to forward slashes |
| Coarse undo on failure | Med | Undo block + per-item checkpoints |

## Rollback Plan

1. Delete `groove-stem-auto-router.lua` and `route_map.json`
2. REAPER undo reverts all insertions as a single step
3. GUID calibration cleared via `ExtState` removal

## Dependencies

- REAPER 6.0+ (runtime detection for newer features)
- No external packages — inline JSON parser bundled

## Success Criteria

- [ ] 10-stem folder routes all files to correct tracks in < 2s
- [ ] Name collisions resolved via GUID calibration (zero false matches)
- [ ] Overflow stems placed in lanes or new tracks per config
- [ ] Single undo block groups all insertions as one reversible action
- [ ] `route_map.json` changes applied on next run without restart
