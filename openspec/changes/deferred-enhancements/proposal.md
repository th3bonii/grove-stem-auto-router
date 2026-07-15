# Proposal: Deferred Enhancements

## Intent
Complete the 4 deferred tasks from core-optimizations: UI heatmap/lazy-load, AI retry/backoff, learning corrections wiring, and route_map.json persistence.

## Scope
- UI heatmap + lazy-load sidebar
- AI retry/backoff for synchronous curl
- Learning.record_corrections() in GUI track reassign
- Session state persistence to route_map.json

## Approach
Four independent work streams, each revertible. Heatmap uses table cells. Lazy-load chunks by scroll. AI retry wraps os.execute in loop. Learning wires to _select_track_for_stem. Persistence adds state block to Config.
