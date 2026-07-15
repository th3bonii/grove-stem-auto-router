# Proposal: Core Optimizations

## Intent

Transform the Grove Stem Auto-Router from a working prototype into a production-grade routing engine with robust matching, responsive UI, resilient AI integration, and zero silent failures.

## Scope

### In Scope
- **Matching Engine**: token-specificity tiebreaker, auto noise-prefix detection, alias-aware number filter, weighted scoring
- **Learning Integration**: wire dead `R.Learning` module into pipeline
- **UI**: lazy-load sidebar items, stem-occurrence heatmap, visual alerts replacing console-only errors
- **AI**: auto-trigger resolve after scan, retry/backoff, fallback on provider failure
- **Robustness**: session state persistence to `route_map.json` with rollback snapshots
- **Tests**: comprehensive coverage for all new paths

### Out of Scope
- New spec-level capabilities (existing specs unchanged)
- Python proxy rewrite or removal
- Full UI redesign
- Performance optimization of ReaImGui rendering itself
- Multi-language support

## Capabilities

No new or modified specs. All changes are implementation-level refinements of existing specifications.

## Approach

Six work streams in dependency order:

1. **Matching fixes** — number filter fix, tiebreaker, auto noise detection
2. **Weighted scoring** — alias-resolved matches weighted higher than raw-string
3. **Learning integration** — connect `R.Learning.match()` + `record_corrections()` to pipeline
4. **AI auto-trigger** — hook into `scan_folder()` with retry/backoff + visible errors
5. **UI improvements** — heatmap, lazy-load, visual alert component
6. **Persistence & rollback** — session state block in `route_map.json`

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/matching-engine.lua` | Modified | Tokenize filter, tiebreaker, weighted score, noise detection |
| `lib/config.lua` | Modified | Session ignore set, persistence helpers |
| `lib/import.lua` | Modified | Wire learning into pipeline |
| `lib/learning.lua` | Modified | Connect to pipeline (was unreferenced) |
| `gui/main_window.lua` | Modified | AI auto-trigger, heatmap, lazy-load, visual alerts |
| `lib/orphan.lua` | Modified | Retry/backoff support |
| `route_map.json` | Modified | State block added |
| `tests/test_matching_engine.lua` | Extended | New scenarios |
| `tests/test_learning.lua` | Extended | Learning pipeline tests |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Auto-detect false positives filter valid tokens | Low | Only filter tokens NOT in alias map |
| Scoring regressions | Low | Full test suite before/after each change |
| Learning integration introduces bugs | Medium | Incremental wiring with test coverage |
| AI resolve auto-trigger costs | Medium | Opt-in flag, no auto without API key |
| UI changes break existing layout | Low | Sidebar state preserved, additive widgets |

## Rollback Plan

Each fix is independently revertible. Revert `matching-engine.lua` for matching fixes. Revert `import.lua` for learning. Revert `main_window.lua` for UI/AI changes. Revert `config.lua` + `route_map.json` for persistence.

## Dependencies

None (pure Lua, no new external deps).

## Success Criteria

- [ ] "808" maps to "sub_bass" via alias
- [ ] Noise prefixes (e.g. "Lassie_beat") auto-filtered without manual config
- [ ] "Rbass vs BEAT" ties resolved by token specificity
- [ ] Learning module is called in the matching pipeline
- [ ] AI resolve triggers automatically after scan when API key present
- [ ] UI shows visual alerts instead of console-only messages
- [ ] Session state persists across restarts with rollback capability
- [ ] No regressions on existing test suite
