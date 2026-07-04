# Delta for Route Map Config

## MODIFIED Requirements

### Requirement: Schema

The JSON MUST define these keys: `alias`, `keywords_ignore`, `overflow_behavior`, `max_lanes_per_track`, `alias_priority`, `fuzzy_threshold`, and optionally `categories` and `ai_config`.
(Previously: alias mapped filename keyword arrays to canonical category names; categories mapped category → destination names)

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `alias` | object | Yes | Maps semantic synonyms to canonical names (e.g. `["vox","vocals"] → "vocal"`) |
| `keywords_ignore` | string[] | Yes | Tokens stripped from filenames |
| `overflow_behavior` | `"lanes"` \| `"new_track"` | Yes | Global overflow strategy |
| `max_lanes_per_track` | integer ≥ 1 | Yes | Lane cap |
| `categories` | object | No | Per-category folder/overflow overrides |
| `alias_priority` | `"first-match"` \| `"best-match"` | Yes | Match resolution strategy |
| `fuzzy_threshold` | float 0.0–1.0 | Yes | Minimum token-intersection for fuzzy fallback |
| `ai_config` | object | No | AI proxy host, port, model |

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| New keys loaded | valid JSON with all new keys | parsing completes | all fields available |
| Best-match mode | alias_priority = "best-match", two aliases score 0.6 and 0.9 | matching runs | highest-score alias wins |
| Missing required key | file missing fuzzy_threshold | validation | error logged, defaults used |

## REMOVED Requirements

### Requirement: Categories as Name Mapping

(Reason: `categories → names` assumption removed. Aliases now map semantic synonyms, not destination names. Token-intersection replaces the name-based category-to-track link.)
