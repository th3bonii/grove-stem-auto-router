# Exploration: Deferred Enhancements

## Items

1. **UI Heatmap + Lazy-Load** — Visualize stem-track density in sidebar; load items in chunks of 50
2. **AI Retry/Backoff** — Retry curl up to 2 times with backoff on timeout (sync version for main)
3. **Learning.record_corrections()** — Wire learning corrections into the GUI reassignment path
4. **route_map.json Persistence** — Save/restore session state to route_map.json

## Current State

All items are deferred from core-optimizations. The UI currently renders all stems at once in a scrollable child. AI curl is synchronous with no retry. Learning module stores but never applies corrections. UI state persists via reaper.ExtState, not route_map.json.

## Approaches

- **Heatmap**: ReaImGui table with colored cells per stem-track pair
- **Lazy-load**: Chunk rendering via ipairs slice based on scroll Y
- **AI Retry**: Loop around os.execute curl with exponential backoff
- **Learning Wiring**: Call record_corrections() after manual combo reassign
- **Persistence**: Save/load state block in route_map.json via Config._data
