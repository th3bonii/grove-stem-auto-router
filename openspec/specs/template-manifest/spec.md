# Template Manifest Specification

## Purpose

Run a preflight scan before import that shows the user available tracks, their categories, calibration status, and potential issues. Reduces surprises during import.

## Requirements

### Requirement: Preflight Scan

The system MUST scan all visible REAPER tracks before import begins, collecting: name, index, GUID, folder depth, calibration status.

- GIVEN 12 tracks in the project
- WHEN preflight scan runs
- THEN 12 tracks scanned with full metadata collected

### Requirement: Manifest Display

The system MUST display a ReaImGui table: track name, index, calibrated (yes/no), folder depth, overflow capacity.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Calibrated shown | 3 of 12 tracks calibrated | manifest opens | calibrated tracks marked ✓ in table |
| Empty project | no tracks exist | manifest opens | "No tracks" message, import blocked |

### Requirement: Pre-Import Validation

The system MUST flag issues before import: duplicate track names, missing target categories, insufficient overflow capacity.

- GIVEN 5 stems need category "cowbell" but no track matches
- WHEN validation runs
- THEN issue flagged with "Missing target category" warning
- AND user may cancel or proceed
