# Delta for Stem Import Engine

## MODIFIED Requirements

### Requirement: Name Normalization

The system MUST normalize each stem filename: strip `keywords_ignore` tokens, then replace alias-matched tokens with their canonical category name per `route_map.json`. The normalized name MUST be stored and displayed per stem in the GUI.
(Previously: normalization was internal only — no display requirement)

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Alias with display | route_map maps `"808" → "sub_bass"`, `keywords_ignore = ["loop"]` | processing `"808_loop.wav"` | category = `"sub_bass"`, display name = `"808"` |
| Ignore-only display | `keywords_ignore = ["v1","mix"]`, no alias | processing `"kick_v1_mix.wav"` | category = `"kick"`, display name = `"kick"` |

### Requirement: Track Name Matching

The system MUST delegate matching to the matching-engine module using token-intersection comparison. The import engine sends normalized category and track names; the matching engine returns match results or orphan status.
(Previously: case-insensitive name equality comparison inline)

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Token match via engine | track `"Kick"`, stem category `"kick_sub"` | import delegates to engine | shared token `["kick"]`, intersection = 1.0, stem assigned |
| No match to orphans | stem `"cowbell"`, no track matches | engine returns empty | stem routed to orphan handling |

### Requirement: GUID Calibration Override

The matching engine MUST use calibrated GUID as the primary matcher — checked before token-intersection or name comparison. If a stem has a known GUID target, it matches immediately without name analysis.
(Previously: GUID used only as collision tiebreaker after name matching)

- GIVEN a stem calibrated to track GUID `{A1B2}` and the track name differs
- WHEN matching engine runs
- THEN stem maps to the calibrated track via GUID before any name comparison
- AND no name-based matching is attempted

### Requirement: Media Insertion

The system MUST insert matched stems as media items at project position 0.0 on their assigned track. Each item MUST inherit the track's color. Wrapped in `Undo_BeginBlock`/`EndBlock` and `PreventUIRefresh`.
(Previously: no color inheritance requirement)

- GIVEN 8 stems matched to tracks with various colors
- WHEN insertion runs
- THEN all 8 items created at 0.0, each matching track color
- AND REAPER undo shows one "Import Stems" entry
