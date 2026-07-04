# Orphan Handling Specification

## Purpose

Collect stems that failed all matching paths, display them in a user-selectable GUI, and support auto-insertion as new REAPER tracks.

## Requirements

### Requirement: Orphan Collection

The system MUST collect all stems returning zero matches from the matching engine into an orphan list with metadata: filename, attempted tokens, failure reason.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Orphans detected | 15 stems, 12 matched, 3 unmatched | collection runs | 3 orphans stored with reasons |
| All matched | 15 stems, all matched | collection runs | empty orphan list, no GUI |

### Requirement: GUI Display

The system MUST display orphans in a ReaImGui table with columns: filename, proposed category, reason. The table MUST support multi-select.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Orphans shown | 3 orphans collected | GUI opens | table shows 3 rows with metadata |
| Empty state | 0 orphans | GUI opens | "No orphans" message displayed |

### Requirement: Auto-Insert as Tracks

When the user confirms insertion, the system MUST create new tracks below the last matched track group, insert stems at position 0.0, and inherit folder structure.

- GIVEN user selects 2 orphans and clicks Insert
- WHEN insertion runs
- THEN 2 new tracks created below last matched track group
- AND stems inserted at 0.0, folder depth preserved
