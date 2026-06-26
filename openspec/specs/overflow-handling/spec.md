# Overflow Handling Specification

## Purpose

Define behavior when more stems match a category than available REAPER tracks: insert surplus into Fixed Lanes or create new tracks below the category group, configurable per `overflow_behavior`.

## Requirements

### Requirement: Lanes Mode

When `overflow_behavior = "lanes"`, the system MUST insert surplus stems as additional lanes on the matched track using `SetTrackLaneComping` (REAPER 6.0+).

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Surplus to lanes | 3 stems match a track with 1 slot | lanes mode processes | 1 stem in main lane, 2 added as extra lanes |
| API fallback | lanes mode set but REAPER < 6.0 (no Fixed Lanes API) | overflow runs | falls back to `"new_track"`, console note emitted |

### Requirement: New Track Mode

When `overflow_behavior = "new_track"`, the system MUST create a new track immediately below the last matched category track with matching `I_FOLDERDEPTH`.

- GIVEN 3 stems matching track `"Kick"` at index 5
- WHEN `new_track` processes surplus
- THEN track index 6 is created with surplus stem
- AND `I_FOLDERDEPTH` matches the original category track's folder state

### Requirement: Max Lanes Cap

When lanes mode is active, the system MUST NOT exceed `max_lanes_per_track`. Stems beyond the cap fall back to new track creation.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Hit lane cap | `max_lanes_per_track = 3` and 6 stems match one track | lanes mode processes | 3 stems in lanes, 3 as new tracks below |
| No cap set | `max_lanes_per_track = 0` | overflow runs | infinite lanes allowed (capped only by REAPER) |

### Requirement: Per-Category Override

If `route_map.json` defines per-category `overflow_behavior` in the `categories` object, those values MUST override the global setting for that category.

- GIVEN global `overflow_behavior = "lanes"` but `categories.sub_bass.overflow_behavior = "new_track"`
- WHEN sub_bass stems overflow
- THEN new tracks are created (not lanes)

### Requirement: Folder Depth Integrity

When creating new overflow tracks in folder tracks, the system MUST set `I_FOLDERDEPTH` so that the folder structure remains valid.

- GIVEN the original category track is a folder (I_FOLDERDEPTH = 1)
- WHEN a new overflow track is created below it
- THEN the new track gets I_FOLDERDEPTH = 0 (child, not folder)
- AND the folder end track stays unchanged
