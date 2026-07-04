# Delta for Overflow Handling

## MODIFIED Requirements

### Requirement: Lanes Mode

When `overflow_behavior = "lanes"`, the system MUST detect REAPER version. If REAPER 7+, use `SetMediaTrackLanes` for native Fixed Lanes support. Otherwise fall back to `SetTrackLaneComping` (REAPER 6.0+).
(Previously: only used SetTrackLaneComping for REAPER 6.0+)

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| REAPER 7 lanes | overflow_behavior = "lanes", REAPER 7 detected | overflow runs | uses native SetMediaTrackLanes API |
| REAPER 6 fallback | overflow_behavior = "lanes", REAPER 6 detected | overflow runs | uses SetTrackLaneComping, console notice |

### Requirement: New Track Mode

When `overflow_behavior = "new_track"`, the system MUST detect the parent folder by walking the `I_FOLDERDEPTH` chain upward from the matched track, then create new tracks inside the same folder.
(Previously: created track below matched track and matched I_FOLDERDEPTH value)

- GIVEN matched track is inside folder A (depth chain: root → folder A)
- WHEN new track overflow runs for 3 surplus stems
- THEN 3 new tracks created inside folder A, after the matched track
- AND folder structure remains valid

### Requirement: Folder Depth Integrity

When creating overflow tracks, the system MUST use the category from the match context (already resolved during matching) instead of recalculating from filename.
(Previously: recalculated category by re-parsing filename)

- GIVEN a stem matched to category "kick" via token-intersection
- WHEN overflow creates a new track for it
- THEN the category context "kick" is passed directly
- AND no filename re-parsing occurs
