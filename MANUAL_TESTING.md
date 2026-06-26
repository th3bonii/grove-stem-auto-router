# Grove Stem Auto-Router — Manual Test Scenarios

## Setup

1. Place `groove-stem-auto-router.lua` and `route_map.json` in REAPER's Scripts directory (`Options → Show REAPER resource path... → Scripts/`)
2. In REAPER: `Actions → Show action list → New action → Load ReaScript` → select the `.lua` file
3. Create or open a REAPER project with named tracks matching route_map categories (e.g., "Kick", "Snare", "Vocal", etc.)

---

## 1. Basic Offline Import

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 1.1 | Simple match | 1. Create folder with `Kick_01.wav`, `Snare_01.wav`, `Vocal_01.wav`<br>2. Place folder next to script<br>3. Run action | Each stem inserted at 0:00 on its matching track |
| 1.2 | Case‑insensitive | 1. Create `KICK_01.WAV`, `SNARE_01.WAV`<br>2. Tracks named "Kick", "Snare"<br>3. Run | Both match regardless of case |
| 1.3 | No audio files | 1. Empty folder or folder with only `.txt` / `.mid` files<br>2. Run | Console: "No audio files found" |
| 1.4 | Mixed audio formats | 1. `Kick.wav`, `Snare.flac`, `Vocal.mp3`<br>2. Run | All three inserted correctly |
| 1.5 | No matching tracks | 1. File named `Cowbell.wav`<br>2. No track named "Cowbell" or mapped alias<br>3. Run | Console: "No track match for 'Cowbell.wav'" – stem skipped |

---

## 2. Alias Mapping (route_map.json)

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 2.1 | Direct alias match | 1. `808_Bass.wav` – alias `"808": "sub_bass"`<br>2. Track named "sub_bass"<br>3. Run | Routes to sub_bass track |
| 2.2 | Multiple variants | 1. `Vox_Hook.wav`, `Lead_Vocal.wav`, `Double.wav`<br>2. Track named "vocals"<br>3. Run | All three route to vocals track |
| 2.3 | Ignored keywords stripped | 1. `Kick_Mix_Dry.wav`<br>2. "mix", "dry" in `keywords_ignore`<br>3. Track named "Kick" | Routes to Kick (mix/dry stripped) |
| 2.4 | No alias → first token | 1. `Custom_Sound.wav` – no alias for "custom" or "sound"<br>2. Track named "custom"<br>3. Run | Falls back to "custom" as category |
| 2.5 | Alias precedence | 1. `808_Sub_Bassline.wav` – aliases: `"808"→"sub_bass"`, `"sub"→"sub_bass"`, `"bassline"→"sub_bass"`<br>2. Run | Routes to sub_bass (first matching alias wins) |

---

## 3. Overflow Behavior

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 3.1 | Lane mode (default) | 1. `config.overflow_behavior = "lanes"`, `max_lanes_per_track = 6`<br>2. One track named "Fx", 3 files: `FX_Riser.wav`, `FX_Sweep.wav`, `FX_Impact.wav`<br>3. Run | First file on main lane, others on lanes 2-3 |
| 3.2 | Lane cap reached | 1. Same track, 8 files (max_lanes=6)<br>2. Run | Files 1-6 in lanes, files 7-8 create new tracks below Fx |
| 3.3 | New track mode | 1. `config.overflow_behavior = "new_track"` (global)<br>2. 3 percussion stems, 1 track named "Percussion"<br>3. Run | First stem on Percussion, stems 2-3 on "Percussion - Stem2", "Percussion - Stem3" below |
| 3.4 | Per-category override | 1. Global = "lanes", `categories.sub_bass.overflow_behavior = "new_track"`<br>2. 3 sub_bass stems, 1 track named "sub_bass"<br>3. Run | sub_bass uses new_track despite global lanes |
| 3.5 | Fallback on missing API | 1. Old REAPER (< 6.0, no Fixed Lanes)<br>2. `overflow_behavior = "lanes"`<br>3. Run | Console: "Fixed Lanes API unavailable" – falls back to new_track |

---

## 4. Calibration System

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 4.1 | Calibrate tracks | 1. Select 3 tracks in REAPER<br>2. Run script with `--calibrate` flag<br>3. Click OK | Console: "Calibration saved 3 track GUID(s)" |
| 4.2 | Calibration cancels | 1. Select 0 tracks<br>2. Run with `--calibrate` | Console: "No tracks selected. Calibration cancelled." |
| 4.3 | Calibration resolves collision | 1. Two tracks named "Kick" (main + parallel)<br>2. Calibrate only the main one<br>3. Run import with `Kick_01.wav` | Routes to calibrated main Kick, not the parallel |
| 4.4 | Stale GUID warning | 1. Calibrate, then delete that track<br>2. Run import | Console: "N stale calibration GUID(s) found. Falling back to name match for those." |
| 4.5 | No calibration = name match | 1. No calibration data stored<br>2. Run import | Pure name matching works, no warnings |

---

## 5. Configuration Edge Cases

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 5.1 | Missing route_map.json | 1. Delete route_map.json<br>2. Run | Console: "not found. Using built-in defaults." – script works with empty defaults |
| 5.2 | Invalid JSON | 1. `route_map.json` content: `{ broken: yes }`<br>2. Run | Console: "JSON parse error. Using built-in defaults." |
| 5.3 | Empty file | 1. `route_map.json` is empty<br>2. Run | Console: "is empty. Using built-in defaults." |
| 5.4 | Trailing commas | 1. `"alias": {"kick": "bass", "snare": "drums",}`<br>2. Run | Parser accepts trailing comma, config loads normally |
| 5.5 | Missing optional keys | 1. `route_map.json` with only `alias` and `keywords_ignore`<br>2. Run | Defaults fill overflow_behavior, max_lanes_per_track, categories |

---

## 6. Undo / Rollback

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 6.1 | Single undo restores all | 1. Import 5 stems<br>2. Press Ctrl+Z / Cmd+Z once | All 5 items removed in one undo step |
| 6.2 | Overflow tracks undone | 1. Import with overflow creating new tracks<br>2. Undo | New tracks removed, original project state restored |

---

## 7. Performance

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 7.1 | 10 stems, 5 categories | 1. 10 files, 5 matched tracks<br>2. Run | Complete in < 2 seconds |
| 7.2 | 50 stems, 8 categories | 1. 50 files matching 8 track categories<br>2. Run | Complete in < 5 seconds |

---

## 8. Japanese / Unicode Filenames

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 8.1 | Unicode alias | 1. Add `"ボーカル": "vocals"` to route_map.json<br>2. File named `ボーカル_Main.wav`, track "vocals"<br>3. Run | Routes to vocals track |
| 8.2 | Cyrillic filenames | 1. `Вокал_Основной.wav`, track "Vocal"<br>2. No cyrillic alias<br>3. Run | Falls back to first token ("вокал") – no match, console warning |

---

## Test Log Template

```
Date: ________
REAPER version: ________
Script version: ________

Scenarios run: ____ / ____
PASS: ____
FAIL: ____
Blocked: ____

Notes:
______________________________________________
```
