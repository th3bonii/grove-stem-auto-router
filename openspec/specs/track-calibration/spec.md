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

Each run MUST verify stored GUIDs still point to valid tracks via `BR_GetMediaTrackByGUID`. Valid GUIDs MUST be passed to the matching engine as primary match targets — checked before token-intersection or name matching. Invalid GUIDs MUST emit a warning and fall back to token matching.
(Previously: GUID used only as collision tiebreaker after name matching)

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| GUID as primary | stored GUID points to existing track, name differs from stem | matching runs | GUID match wins, no name comparison |
| Stale GUID | GUID for deleted track | validation runs | console warning, falls back to token matching |

### Requirement: Calibration Is Optional

The system MUST work correctly WITHOUT calibration data. When calibration data IS present, calibrated tracks are matched first via token-intersection before non-calibrated tracks are attempted.
(Previously: name matching was the sole default path)

- GIVEN no "TargetGUIDs" ExtState exists
- WHEN the script runs
- THEN all matching uses token-intersection against all tracks
- AND no warnings about missing calibration emitted

### Requirement: GUID Storage Format

GUIDs MUST be stored as a JSON array of hex strings for portability.

- GIVEN tracks with GUIDs `{A1B2...}` and `{C3D4...}`
- WHEN calibration persists
- THEN ExtState contains `["A1B2...", "C3D4..."]`
