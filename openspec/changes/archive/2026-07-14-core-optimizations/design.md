# Design: Core Optimizations

## Technical Approach

Six independent work streams implemented in dependency order. Each is independently revertible. The matching engine gets a specificity tiebreaker, alias-aware number filter, auto noise-prefix detection, and weighted scoring. The learning module is wired into the pipeline. AI resolve becomes automatic after scan with retry/backoff. UI gains lazy-load, heatmap, and visual alerts. Session state persists to `route_map.json`.

## Architecture Decisions

### Decision: Token-specificity tiebreaker

**Choice**: Extend existing `(score, alias_count)` comparison to prefer tracks with more raw tokens when both are tied.
**Alternatives**: New dedicated tiebreaker phase, BLEU score, TF-IDF.
**Rationale**: Minimal code change (3 lines). Already implemented for calibrated path; replicate to token-intersection path. No new concepts.

### Decision: Weighted scoring formula

**Choice**: `(alias_shared * 1.0 + raw_shared * 0.3) / min(#stem, #track)`
**Alternatives**: Pure alias scoring, TF-IDF vector cosine similarity.
**Rationale**: Simple arithmetical weighting rewards alias-resolved matches without breaking raw-string matches entirely. Thresholds remain at 0.5.

### Decision: Auto noise-prefix detection

**Choice**: Pre-scan all stems, count token frequency, add tokens >60% frequency AND not in alias map to session ignore set in `R.Config`.
**Alternatives**: Manual per-project config, ML prefix detection.
**Rationale**: No user config needed, works for any project prefix, runtime-only (not persisted).

### Decision: AI auto-trigger with retry

**Choice**: Hook `_run_ai_curl("review")` into `scan_folder()` after matching completes. Retry up to 3 times with 2s backoff. Show visible error dialog if all fail.
**Alternatives**: Blocking synchronous curl, no retry.
**Rationale**: Non-blocking background curl already exists; just hook and add retry loop.

### Decision: UI heatmap + lazy-load

**Choice**: ReaImGui table with cell coloring for stem-track occurrence density. Sidebar items loaded on-demand by scroll position (chunk size 50).
**Alternatives**: Full canvas rendering, virtual scrolling library.
**Rationale**: ReaImGui table is performant enough for typical stem counts (<500). Lazy-load prevents initial paint freeze.

## Data Flow

```
scan_folder()
  ├── detect_noise_prefix(stems, alias_map)
  │     └── R.Config.set_session_ignore(noise_tokens)
  ├── for each stem:
  │     └── R.MatchingEngine.match(..., noise_aware)
  │           ├── calibrated (guid_map, threshold 0.2)
  │           ├── token-intersection (threshold 0.5, weighted score + tiebreaker)
  │           ├── R.Learning.match() (threshold 0.8, count >= 2)
  │           ├── fuzzy Levenshtein (threshold configurable)
  │           └── orphan (nil)
  ├── collect_orphans()
  ├── if api_key present: _run_ai_curl("review") with retry
  └── import phase:
        ├── insert matched stems
        ├── create new tracks for orphans
        └── visual alerts for failures
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `lib/matching-engine.lua` | Modify | Number filter check alias first, tiebreaker in token-intersection, detect_noise_prefix, weighted score formula |
| `lib/config.lua` | Modify | session_ignore setter, state persist/restore helpers |
| `lib/import.lua` | Modify | Wire learning into run_matching pipeline |
| `lib/learning.lua` | Modify | Ensure match() returns are consumed correctly |
| `gui/main_window.lua` | Modify | Hook AI into scan_folder, add heatmap table, lazy-load sidebar, visual alert component |
| `lib/orphan.lua` | Modify | Retry/backoff support in AI check |
| `route_map.json` | Modify | Add `_state` block for session persistence |
| `tests/test_matching_engine.lua` | Modify | Add noise, tiebreaker, number filter tests |
| `tests/test_learning.lua` | Modify | Add pipeline integration tests |

## Interfaces / Contracts

```lua
-- New/Modified interfaces:
R.MatchingEngine.detect_noise_prefix(stems, alias_map) -> { [token]: true }
R.Config.set_session_ignore(tokens) -> nil
R.Config.get_ignore_set() -> { [token]: true }  -- existing, unchanged signature
R.Config.get_state_block() -> table
R.Config.save_state_block(state) -> nil, err
R.Learning.match(stem_name, track_map) -> track, score (existing, now wired)
```

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | Number filter with alias | Expect "808" preserved when alias_map["808"] exists |
| Unit | Tiebreaker with token count | Two tracks same score, more tokens wins |
| Unit | Weighted score formula | Alias match scores higher than raw match |
| Unit | Noise prefix detection | 3 stems "A_B", "A_C", "A_D" → "a" detected as noise |
| Integration | Learning pipeline | Learning.match() called after token-intersection |
| Integration | AI auto-trigger | scan_folder calls _run_ai_curl when API key set |
| E2E | Full Lassie_beat scenario | All stems route to correct tracks |

## Migration / Rollout

- Chained PRs: PR1 (matching fixes + tests), PR2 (learning + scoring), PR3 (AI + UI + persistence)
- Feature flags: none needed
- Backward compatible: yes

## Open Questions

- None
