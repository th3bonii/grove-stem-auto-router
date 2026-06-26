# Route Map Configuration Specification

## Purpose

Provide a user-editable JSON configuration file (`route_map.json`) controlling stem name normalization, overflow behavior, and routing rules. Lives next to the script. Changes apply on next run — no restart needed.

## Requirements

### Requirement: File Location

`route_map.json` MUST reside in the same directory as the script file, discovered via `debug.getinfo(1).source` path resolution.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Side-by-side found | `route_map.json` in script directory | script initializes | config loaded and parsed |
| Missing file | no `route_map.json` exists | script initializes | warning emitted, built-in defaults used |

### Requirement: Schema

The JSON MUST define these top-level keys: `alias`, `keywords_ignore`, `overflow_behavior`, `max_lanes_per_track`.

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `alias` | object: `{string[] → string}` | Yes | Maps filename keyword arrays to canonical category names |
| `keywords_ignore` | string[] | Yes | Tokens stripped from filenames before matching |
| `overflow_behavior` | `"lanes"` \| `"new_track"` | Yes | Global overflow strategy |
| `max_lanes_per_track` | integer ≥ 1 | Yes | Lane cap before falling back to new tracks |
| `categories` | object (optional) | No | Per-category overrides for overflow_behavior |

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Valid schema loads | valid `route_map.json` with all fields | parsing completes | all config fields available |
| Invalid JSON | malformed JSON syntax | inline parser runs | parse error reported, defaults used |
| Missing required key | file missing `max_lanes_per_track` | validation runs | error logged, defaults used |

### Requirement: Runtime Reload

Config changes MUST apply on the next script execution without restarting REAPER.

- GIVEN the user edits `route_map.json` while REAPER is open
- WHEN the script runs again
- THEN the new configuration is loaded
- AND no stale config is cached between runs

### Requirement: Inline JSON Parser

The script MUST bundle an inline JSON parser (zero external dependencies) supporting objects, arrays, strings, numbers, booleans, and null.

- GIVEN a JSON string with nested objects and arrays
- WHEN the inline parser processes it
- THEN the result matches `lua-table` deserialization correctly
