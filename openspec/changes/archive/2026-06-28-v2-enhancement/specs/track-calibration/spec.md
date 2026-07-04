# Delta for Track Calibration

## MODIFIED Requirements

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
