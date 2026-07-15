# Design: Deferred Enhancements

## 1. Heatmap + Lazy-Load
- Heatmap: ReaImGui table with `ImGui_Table` + cell coloring based on stem-track density
- Lazy-load: Track visible scroll region via `ImGui_GetScrollY`/`ImGui_GetScrollMaxY`; render chunk of 50 stems

## 2. AI Retry/Backoff (sync)
- In `_run_ai_curl()`, wrap `os.execute` + polling read in retry loop up to 2 attempts
- 2s exponential backoff between retries
- Log each attempt; show error after final failure

## 3. Learning Corrections Wiring
- In `_select_track_for_stem()`, after reassignment call `R.Learning.record_corrections(state.assignments)`
- Learning.match() already in pipeline; now corrections persist

## 4. Persistence
- Add `_state` block to `route_map.json` (scroll_y, sidebar_visible, recent_guids)
- Save via same trigger as save_prefs()
- Load during Config.load()
