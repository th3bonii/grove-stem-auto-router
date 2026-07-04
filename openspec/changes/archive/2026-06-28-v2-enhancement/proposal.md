# Proposal: V2 Enhancement — Matching Engine & Architecture Overhaul

## Intent

"Lead Vocal" never matches alias "vocals" — stems silently drop. GUID ignored as primary matcher. Twelve compounding issues: broken folders, merge undo, no orphan or fuzzy resolution.

## Scope

### In Scope
- Matching engine: token-intersection, Levenshtein fuzzy, GUID primary
- route_map.json alias restructure (shared tokens, not categories)
- Orphan handling: GUI + create tracks
- Overflow: folder-aware, REAPER 7 Fixed Lanes, context
- AI Hybrid Layer: Python proxy, OSC, LLM resolution
- Template manifest: scan
- Undo flag fix, track color inheritance

### Out of Scope
- Multi-project batch, cross-DAW, cloud sync, mobile/remote

## Capabilities

> Contract with sdd-spec. Existing specs at `openspec/specs/`.

### New
- `matching-engine`: Token-intersection, shared-token alias
- `fuzzy-matching`: Levenshtein, threshold
- `orphan-handling`: Collect, GUI, create
- `ai-hybrid-layer`: Python proxy, OSC, LLM

### Modified
- `stem-import-engine`: Matching extracted; context to overflow
- `track-calibration`: GUID primary
- `route-map-config`: Token aliases; fuzzy_threshold, ai_config
- `overflow-handling`: Folder-aware, Fixed Lanes, context

## Approach

1. `matching-engine.lua` — token-intersection
2. `fuzzy.lua` — Levenshtein
3. `import.lua` — GUID → fuzzy → token → name chain
4. `orphan.lua` — collect, GUI, create
5. `overflow.lua` — folder-depth, Fixed Lanes, context
6. `ai-proxy/main.py` — OSC server
7. GUI — orphan table, calibration, manifest

## Affected Areas

| Area | Impact | Summary |
|------|--------|---------|
| `lib/import.lua` | M | Matching extracted |
| `lib/matching-engine.lua` | N | Token-intersection |
| `lib/fuzzy.lua` | N | Levenshtein |
| `lib/orphan.lua` | N | Collect + create |
| `lib/overflow.lua` | M | Folder-depth, Fixed Lanes |
| `lib/calibration.lua` | M | GUID primary |
| `lib/config.lua` | M | New schema |
| `gui/main_window.lua` | M | Orphan + manifest |
| `route_map.json` | M | Token aliases |
| `ai-proxy/main.py` | N | OSC server |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Token over/under-match | Med | Weights |
| Python dependency | Low | Fallback |
| Fixed Lanes < REAPER 7 | Low | Fallback |
| Routing regression | Med | MANUAL_TESTING.md |

## Rollback Plan

Git revert v2 branch. Restore `route_map.json`. Exact-string fallback in `matching-engine.lua` preserves v1 behavior.

## Dependencies

- Python 3.10+ (AI proxy — optional, degrades safe)
- REAPER 7+ (Fixed Lanes — optional, degrades safe)
- ReaImGui (orphan/manifest)

## Success Criteria

- [ ] Token match: "Lead Vocal" → "vocals"
- [ ] GUID skips name matching
- [ ] Orphans in GUI, auto-created
- [ ] Fuzzy: "Kicck" → "Kick" (≤2 edits)
- [ ] Overflow inside parent folder
- [ ] REAPER 7 Fixed Lanes active
- [ ] Undo per run, no merge
- [ ] Items inherit track color
