# Stem Import Engine Specification

## Purpose

Scan stem audio directory, normalize filenames via `route_map.json` synonyms, match to REAPER tracks by name or calibrated GUID, and insert media items at project start in a single undo block.

## Requirements

### Requirement: Scan Audio Files

The system MUST scan the configured directory and collect all `.wav`, `.flac`, and `.mp3` files.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Read stem folder | directory with 10 `.wav` stems | scan runs | 10 files found |
| Non-audio ignored | directory with audio + `.txt` files | scan runs | only audio files collected |

### Requirement: Name Normalization

The system MUST normalize each stem filename: strip `keywords_ignore` tokens, then replace alias-matched tokens with their canonical category name per `route_map.json`.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Alias substitution | route_map maps `"808" → "sub_bass"`, `keywords_ignore = ["loop"]` | processing `"808_loop.wav"` | category = `"sub_bass"` |
| Ignore-only (no alias) | `keywords_ignore = ["v1","mix"]`, no alias match | processing `"kick_v1_mix.wav"` | category = `"kick"` |

### Requirement: Track Name Matching

The system MUST match each normalized category to a REAPER track by case-insensitive name comparison.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Case-insensitive match | track `"KICK"` and stem category `"kick"` | matching runs | stem assigned to `"KICK"` |
| No match warning | stem category `"cowbell"`, no track matches | matching runs | console warning emitted, stem skipped |

### Requirement: GUID Calibration Override

If target GUIDs are stored via `SetProjExtState`, the system MUST use GUID matching instead of name matching for disambiguation on name collisions.

- GIVEN two stems both matching `"kick"` and one calibrated GUID for track `"Kick_L"`
- WHEN matching runs
- THEN the correct stem maps to `"Kick_L"` via GUID
- AND the other stem is handled via overflow

### Requirement: Media Insertion

The system MUST insert matched stems as media items at project position 0.0 on their assigned track, wrapped in `Undo_BeginBlock`/`EndBlock` and `PreventUIRefresh`.

- GIVEN 8 stems matched to tracks
- WHEN insertion runs
- THEN all 8 items are created at position 0.0
- AND REAPER undo shows one `"Import Stems"` entry

### Requirement: Cross-Platform Paths

All file paths MUST be normalized to forward slashes regardless of OS.

- GIVEN a Windows path `"C:\stems\kick.wav"`
- WHEN the script processes the path
- THEN it is stored as `"C:/stems/kick.wav"`
