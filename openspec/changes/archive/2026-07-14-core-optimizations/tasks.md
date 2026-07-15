# Tasks: Core Optimizations

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 650-850 |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR1: matching fixes + tests → PR2: learning integration + scoring → PR3: AI auto-trigger + UI/heatmap |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Matching fixes (number filter, token-specificity tiebreaker, auto noise detection) + tests | PR1 | Stacked to main; independent |
| 2 | Learning module integration + weighted scoring | PR2 | Depends on PR1 |
| 3 | AI resolve auto-trigger + visual alerts + UI heatmap/lazy load | PR3 | Depends on PR2 |

## Phase 1: Matching Engine Fixes & Tests

- [x] 1.1 In `lib/matching-engine.lua` `tokenize()`: check alias map before discarding pure-number tokens (preserve "808") — **Done (pre-existing)**
- [x] 1.2 Add `detect_noise_prefix(stems, alias_map)` helper; add tokens in >60% stems (not in alias) to session ignore set in `lib/config.lua` — **Done (pre-existing)**
- [x] 1.3 Implement token-specificity tiebreaker in `score()` / `match()`: prefer more tokens / longer matched token when score+alias tie — **Done (pre-existing)**
- [x] 1.4 Extend `tests/test_matching_engine.lua`: noise prefix, multi-token, number filter, tiebreaker, alias-map scenarios — **Done (pre-existing)**

## Phase 2: Learning Integration & Weighted Scoring

- [x] 2.1 In `lib/matching-engine.lua` `match()`: wire `R.Learning.match()` as tiebreaker (score ≥0.8, count ≥2) — **Done (pre-existing)**
- [ ] 2.2 Wire `R.Learning.record_corrections()` to GUI manual reassignment path in `gui/main_window.lua` — **Deferred** (manual reassignments use track combo, not learning corrections)
- [x] 2.3 Update `score()` to weighted formula: `(alias_shared*1.0 + raw_shared*0.3) / min(#stem,#track)` — **Done (this session)**
- [x] 2.4 Add learning-pipeline tests in `tests/test_learning.lua` — **Done (pre-existing)**

## Phase 3: AI Auto-Trigger, UI & Robustness

- [x] 3.1 In `gui/main_window.lua` `scan_folder()`: auto-launch `_run_ai_curl(true, true)` after matching when API key present — **Done (pre-existing)**
- [x] 3.2 Add retry/backoff for AI curl timeout in `_poll_ai_result()` — **Done (this session)**
- [ ] 3.3 Implement lazy-loading of sidebar items and stem-occurrence heatmap widget — **Deferred** (ReaImGui handles inherent scrolling; heatmap requires design discussion)
- [ ] 3.4 Persist session state to `route_map.json` (state block) with rollback snapshot — **Deferred** (REAPER ExtState already persists UI state; route_map.json is user config)
- [x] 3.5 Add UI visual error/alert component replacing console-only messages — **Done (this session)** — red text + dismiss button

## Phase 4: Cleanup & Verification

- [x] 4.1 Run full test suite; verify no regressions — **122 tests, 121 pass, 1 pre-existing fail**
- [ ] 4.2 Update `README.md` and `MANUAL_TESTING.md` with new capabilities — **Deferred to PR merge**
- [ ] 4.3 Remove dead legacy `R.Import.match()` if unused — **Deferred** (kept for backward compat)
