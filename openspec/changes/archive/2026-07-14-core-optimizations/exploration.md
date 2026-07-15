# Exploration: Core Optimizations for Grove Stem Auto-Router

## Target Change
The **core-optimizations** change targets a comprehensive set of improvements across matching engine accuracy, file scanning performance, JSON configuration parsing, UI UX, AI integration reliability, and system robustness.

## Current State

### Matching Engine (lib/matching-engine.lua)
- **Algorithm**: 4-step pipeline (calibrated GUID, token-intersection, fuzzy Levenshtein, orphan)
- **Scoring**: `score = shared / min(#stem_tokens, #track_tokens)` capped at 1.0
- **Tiebreaker**: Preference for tracks with more alias-map keys
- **Limitations**:
  - Pure-number tokens (e.g., "808") are filtered before alias resolution
  - Noise tokens like "lassie" and "beat" are not ignored, causing ties
  - No multi-pass confidence refinement
  - Learning module is loaded but never invoked
  - AI Resolve runs only on manual button press, not automatically after scan
  - AI errors are logged but not visualized to the user
  - No fallback retry without API key/network

### File Scanning (lib/import.lua, lib/topology-scanner.lua)
- Scans folder on every run, no caching
- Pure-number tokens are filtered early, losing potential alias matches
- No incremental change detection

### JSON Configuration (lib/config.lua)
- Parses tabs/spaces generically but not configurable
- No minification or compression support

### UI (gui/main_window.lua)
- Sidebar scroll height per branch cached (recent improvement)
- No lazy-loading of items
- No visual heatmap of stem occurrences
- Error messages appear only in console/log

### AI Integration (curl layer)
- Uses Lua-native curl for AI reviews
- Falls back to Python proxy only when curl missing
- No fallback model if provider-specific request fails
- No auto-triggering after scan

## Affected Areas
- `lib/matching-engine.lua` — core scoring, tiebreaker, fuzzy logic
- `lib/import.lua` — scanning, name normalization, orphan handling
- `lib/topology-scanner.lua` — directory traversal (potential bottleneck)
- `lib/config.lua` — config loading and parsing
- `gui/main_window.lua` — UI orchestration, matching pipeline kickoff
- `lib/fuzzy.lua` — Levenshtein distance implementation
- `lib/orphan.lua` — orphan collection and AI mapping
- `route_map.json` — alias map, keywords_ignore, thresholds
- `tests/test_matching_engine.lua` — insufficient coverage
- `openspec/changes/*` — spec artifacts need updating

## Approaches

### 1. Automatic Noise Token Detection (Medium effort)
- Pre-scan all stems in current session
- Count token frequency across stems
- Tokens appearing in >60% of stems automatically added to `keywords_ignore` for the session
- Pros: Solves noise problem for any project, not just Lassie_beat
- Cons: Requires runtime config mutation; edge cases with small stem sets

### 2. Improved Score Formula (Low effort)
- Change from `shared / min(#stem, #track)` to `shared / max(#stem, #track)` OR
- Apply weighted factor: `shared / #stem` with lower threshold (e.g., 0.25)
- Pros: Simple, one-line change
- Cons: May affect legitimate matches; does not solve tiebreaker directly

### 3. Weighted Token Scoring (Medium effort)
- Score = (alias_matched_shared * 1.0 + raw_matched_shared * 0.3) / min(#stem, #track)
- Weight alias-resolved matches higher than raw string matches
- Pros: Distinguishes signal vs. noise matches
- Cons: Adds complexity to scoring; threshold recalibration needed

### 4. Multi-pass Matching with Confidence Levels (Medium-High effort)
- Pass 1: High-confidence matches only (both sides have alias-resolved tokens)
- Pass 2: Standard token-intersection
- Pass 3: Low-confidence fuzzy with relaxed threshold
- Pros: Clear separation of concerns, gradual degradation
- Cons: More complex code, more maintenance

### 5. Better Tiebreaker: Token Specificity (Low effort)
- When scores AND alias-counts tie, prefer tracks with more tokens or longer matched tokens
- Fixes "Rbass vs BEAT" confusion
- Pros: Simple, no new concepts
- Cons: Does not solve fundamental noise problem

### 6. Fix Number Filter for 808 (Low effort)
- Check alias map BEFORE filtering pure-number tokens
- Preserve tokens like "808" that map to meaningful aliases
- Pros: Simple one-line change with tangible benefit
- Cons: Only addresses one narrow case

### 7. Integrate Learning Module (Medium effort)
- Wire `R.Learning.match()` into pipeline as post-process or tiebreaker
- Wire `R.Learning.record_corrections()` to manual reassignment UI
- Pros: Leverages existing dead code with persistent learning potential
- Cons: Learning module has its own scoring issues; integration risk

### 8. Comprehensive Test Suite (Medium effort)
- Add end-to-end tests covering:
  - Noise prefix scenarios
  - Multi-token tracks
  - Calibrated matching path
  - Fuzzy fallback edge cases
  - Score formula variations
  - Tie ordering
- Pros: Prevents regressions, validates improvements
- Cons: Test maintenance overhead

### 9. AI Resolve Auto-trigger (Medium effort)
- Hook Lua-native AI review into `scan_folder()` pipeline
- Run automatically after scan when API key configured
- Add visible error dialogs for AI failures
- Add fallback retry mechanism with backoff
- Pros: Automatic orphan resolution, improved user experience
- Cons: API usage costs; need opt-in or quota

### 10. Visual UI Enhancements (Medium effort)
- Add loading states and progress indicators
- Implement lazy-loading for sidebar items
- Generate heatmap visualization of stem occurrences across tracks
- Pros: Improves UX, clarifies matching progress
- Cons: Adds UI complexity

## Recommendation

**Immediate Implementations (Low effort, high impact):**
1. **Fix Number Filter** – Before discarding pure-number tokens, check if they exist in `alias_map`. This preserves "808" → "sub_bass" mapping.
2. **Token Specificity Tiebreaker** – When scores tie, prefer tracks with more tokens or longer matched tokens. This resolves "Rbass vs BEAT" confusion.
3. **Auto-detect Project Prefix Noise** – Pre-scan stems, compute frequency, auto-add frequent tokens to `keywords_ignore` for current session. Solves noise problem generally.

**Short-term Enhancements (Medium effort, high ROI):**
4. **Integrate Learning Module** – Invoke `R.Learning.match()` as tiebreaker after standard matching, and wire `R.Learning.record_corrections()` to GUI corrections.
5. **Weighted Token Scoring** – Adopt weighted formula to give higher weight to alias-resolved matches.
6. **AI Resolve Auto-trigger** – Hook AI review into `scan_folder()` pipeline and add visible UI feedback for failures/retries.
7. **Comprehensive Test Suite** – Expand test coverage for all edge cases listed in findings.

**Optional Future Enhancements (Higher effort):**
8. **Multi-pass Matching with Confidence Levels** – Formalize pass-based decision flow.
9. **Visual Heatmap & Lazy Loading** – Improve UI responsiveness and insight.

## Risks
- **False Positive Noise Detection** – May inadvertently filter meaningful tokens. Mitigate by only ignoring tokens NOT in alias map and limiting to >60% frequency.
- **Scoring Changes Breaking Existing Matches** – Any formula alteration must be validated against existing correct matches.
- **AI Usage Costs** – Auto-triggering AI consumes API credits. Should be opt-in or throttled.
- **Learning Module Bugs** – Integration may surface hidden bugs. Test incrementally.

## Ready for Proposal

Yes – all findings read, all questions answered, concrete approaches identified, risks outlined.

**Proposed Change Scope:**
- Implement fixes #1, #2, #3 #4 #6 #7 #9 #10 in staged fashion
- Expand test suite with new edge cases
- Integrate learning module and weighted scoring
- Hook AI resolve into scan pipeline with UI feedback

(End of file - total 336 lines)
