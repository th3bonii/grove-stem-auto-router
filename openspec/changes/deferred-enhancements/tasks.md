# Tasks: Deferred Enhancements

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: Medium

- [ ] 1.1 UI: Add stem-track heatmap table to sidebar with cell coloring
- [ ] 1.2 UI: Implement lazy-load chunk rendering (50 stems per scroll batch)
- [ ] 2.1 AI: Add retry loop (2 attempts, 2s backoff) to synchronous `_run_ai_curl()`
- [ ] 3.1 Learning: Wire `record_corrections()` in `_select_track_for_stem()` GUI handler
- [ ] 4.1 Config: Add `_state` block save/restore helpers
- [ ] 4.2 Persistence: Save state to route_map.json on UI state changes
