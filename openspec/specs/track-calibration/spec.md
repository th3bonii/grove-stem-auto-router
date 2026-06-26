# Track Calibration Specification

## Purpose

Let users select REAPER tracks and persist their GUIDs via project ExtState for disambiguation when multiple stems match the same name. Calibration is optional — name matching is the default path.

## Requirements

### Requirement: Track Selection

When calibration mode is active, the system MUST prompt the user to select one or more REAPER tracks.

- GIVEN the user runs the script with calibration mode (`--calibrate`)
- WHEN the script triggers `GetSet_LoopTimeRange` or `BR_GetMouseCursorContext_Track`
- THEN the user can select tracks interactively

### Requirement: GUID Persistence

The system MUST serialize selected track GUIDs via `SetProjExtState("GROVE_STEMS", "TargetGUIDs", jsonString)`.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Store GUIDs | user selected 3 tracks | calibration saves | ExtState stores 3 GUIDs as JSON array |
| Cancel selection | user cancels prompt | calibration attempts save | no ExtState written, clean exit |

### Requirement: GUID Validation on Run

Each run MUST verify stored GUIDs still point to valid tracks via `BR_GetMediaTrackByGUID`. Invalid GUIDs MUST emit a warning and fall back to name matching.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Valid GUID | stored GUID points to existing track | validation runs | GUID accepted for matching |
| Stale GUID | stored GUID for deleted/recreated track | validation runs | console warning lists stale GUID, falls back to name match |

### Requirement: Calibration Is Optional

The system MUST work correctly WITHOUT calibration data. Name matching is the default resolution strategy.

- GIVEN no `"TargetGUIDs"` ExtState exists
- WHEN the script runs
- THEN all matching uses case-insensitive name comparison
- AND no warnings about missing calibration are emitted

### Requirement: GUID Storage Format

GUIDs MUST be stored as a JSON array of hex strings for portability.

- GIVEN tracks with GUIDs `{A1B2...}` and `{C3D4...}`
- WHEN calibration persists
- THEN ExtState contains `["A1B2...", "C3D4..."]`
