# Matching Engine Specification

## Purpose

Provide a centralized matching engine that splits names into tokens, computes token-intersection scores, and applies Levenshtein fuzzy fallback. Extracted from inline import logic — consumed by import, calibration, and orphan handling.

## Requirements

### Requirement: Token-Intersection Matching

The system MUST split stem and track names into space-separated lowercase tokens and compute intersection = |shared tokens| / min(|stem tokens|, |track tokens|).

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Full token match | stem "Lead Vocal", track "Vocals Lead" | matching runs | intersection = 2/2 = 1.0 |
| Subset match | stem "Kick Sub", track "Kick" | matching runs | intersection = 1/1 = 1.0 (min) |
| No shared tokens | stem "Kick", track "Snare" | matching runs | intersection = 0/1 = 0.0 |

### Requirement: Levenshtein Fuzzy Fallback

When token-intersection is below `fuzzy_threshold`, the system MUST compute Levenshtein edit distance per token pair and accept matches ≤ 2 edits.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Typo corrected | stem "Kicck", track "Kick" | fuzzy fallback | edit distance = 1, match accepted |
| Excessive edits | stem "Kicckk", track "Kick" | fuzzy fallback | edit distance = 3, match rejected |

### Requirement: Match Priority Chain

The system MUST evaluate matches in order: calibrated GUID → token-intersection → fuzzy → exact name. First match wins.

- GIVEN a stem with calibrated GUID AND a token match
- WHEN matching engine evaluates priority
- THEN GUID match used, token match skipped

### Requirement: Score Threshold

The system MUST NOT return matches scoring below `fuzzy_threshold` (default 0.5). Matches below threshold are treated as no match.

- GIVEN fuzzy_threshold = 0.7 and computed intersection = 0.5
- WHEN matching evaluates the pair
- THEN no match reported for that pair
