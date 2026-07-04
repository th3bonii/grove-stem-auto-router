# Grove Stem Auto-Router — Manual Test Scenarios

## Setup

1. Place the script folder (with `main.lua`, `gui/`, `lib/`, `route_map.json`) in REAPER's Scripts directory (`Options → Show REAPER resource path... → Scripts/`)
2. In REAPER: `Actions → Show action list → New action → Load ReaScript` → select `main.lua`
3. Create or open a REAPER project with named tracks (e.g., "Kick", "Snare", "Vocal", "808", "Fx")
4. Have a folder of FL Studio stem exports (`.wav`, `.flac`, `.mp3`) ready
5. Required: `curl` (built-in on macOS/Linux/Windows 10+)

---

## 1. GUI: Basic Navigation

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 1.1 | Window opens correctly | 1. Run the action from REAPER's Action List<br>2. Observe the window | Window titled "Grove Stem Auto-Router" appears with all sections: STEMS FOLDER row, calibration status, OVERFLOW, AI ASSISTANT, and LOG |
| 1.2 | Layout renders without clipping | 1. Open the GUI<br>2. Resize window freely | Contents reflow; no clipped text or overlapping controls. Window size adapts to content automatically |
| 1.3 | Browse button works | 1. Click **Browse...**<br>2. Navigate to a folder containing `.wav` files<br>3. Select ANY single `.wav` file | Folder path auto-detected from the selected file and displayed in the read-only path field. LOG shows "Folder: /path/to/dir/" |
| 1.4 | Browse persists selection | 1. Browse to a folder, then close and re-open the GUI<br>2. Check the folder path field | Path restored from REAPER ExtState (persisted across sessions) |
| 1.5 | Calibrate works | 1. Select 2-3 tracks in REAPER's track panel<br>2. Click **Calibrate** in the GUI<br>3. Click OK on the message box | LOG shows "Calibration saved: N track(s)." Status changes to "Calibrated: N track(s)" |
| 1.6 | Scan Folder works | 1. Browse to a folder with 5+ `.wav` files<br>2. Click **Scan Folder** | LOG shows "Found N stem(s) across M track(s)". Stem list appears with each stem name and an arrow → showing its assigned track. Orphans listed if any unmatchable stems exist |
| 1.7 | Scan with empty folder | 1. Browse to an empty folder<br>2. Click **Scan Folder** | Error message displayed: "No audio files found in that folder." |

---

## 2. GUI: Stem Assignment

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 2.1 | Stem list shows correctly | 1. Scan a folder with 3+ stems<br>2. Observe the STEMS section | Each stem listed with its filename, a → arrow, and the matched track name (or "(no match)") |
| 2.2 | Click combo shows track dropdown | 1. After scan, click any track name in the STEMS list (the combo box)<br>2. Observe the dropdown | Dropdown opens showing all available REAPER tracks |
| 2.3 | Select track updates assignment | 1. Open a stem's track combo<br>2. Select a different track from the dropdown | Combo closes. The selected track name now shows next to the stem. Assignment updated in-memory |
| 2.4 | Recent track sorting works | 1. Reassign stem A to "Kick", then reassign stem B to "Kick"<br>2. Open any stem's combo<br>3. Check the top of the list | "Kick" appears at the TOP of the dropdown under recent tracks (above the separator). Recently used tracks sort first |
| 2.5 | Recent tracks limited to 20 | 1. Reassign stems to 25 different tracks<br>2. Open a combo and check recent section | Only the 20 most recently used GUIDs are stored; oldest ones dropped |
| 2.6 | Assignment persists after re-scan | 1. Manually reassign stem A to a specific track<br>2. Click **Scan Folder** again<br>3. Check stem A's assignment | Assignment reverts to the engine's auto-match result (manual overrides are per-scan, not persisted — the engine re-evaluates) |
| 2.7 | Original order section after separator | 1. Open a combo and scroll past the separator<br>2. Check the remaining tracks | Non-recent tracks shown below a separator line, in original track index order |

---

## 3. GUI: Orphan Management

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 3.1 | Orphans detected and shown | 1. Scan a folder with file(s) that have no matching REAPER track (e.g. "Cowbell.wav" with no "Cowbell"/perc track, and no alias)<br>2. Observe the ORPHANS section | ORPHANS section appears showing orphan count. Each orphan listed with checkbox, display name, and reason "(no match in any track)" |
| 3.2 | Select All button works | 1. Scan with 3+ orphans<br>2. Click **Select All** | All orphan checkboxes become checked |
| 3.3 | Deselect All button works | 1. Select All first<br>2. Click **Deselect All** | All orphan checkboxes become unchecked |
| 3.4 | Insert Selected as Tracks creates new REAPER tracks | 1. Scan folder with orphans<br>2. Select at least 2 orphans<br>3. Click **Insert Selected as Tracks** | New tracks created in REAPER named after the orphan stem filenames (without extension). Each new track has the orphan stem inserted on it. LOG shows "Inserted N orphan(s) as new tracks." |
| 3.5 | Inserted track placed after category folder | 1. Orphan category is "drums" and there is a drums folder track at index 3<br>2. Insert the orphan | New track placed at index 4 (immediately after the drums folder's last child) |
| 3.6 | Re-scan after insert clears orphans | 1. Insert selected orphans as tracks<br>2. Click **Scan Folder** again | Those stems now match the newly created tracks. Orphan count decreases or disappears |

---

## 4. GUI: Template Manifest

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 4.1 | Show Manifest toggle works | 1. Click **Show Manifest** | Manifest panel appears below calibration status showing all REAPER tracks with Name, GUID (short), Folder depth, and Cal status |
| 4.2 | Manifest shows Name, GUID, depth, Cal | 1. With manifest visible, observe a row | Display format: `1. Kick abcdef123456.. d0 YES` — name, first 12 chars of GUID + "..", folder depth (`d0`, `d1`), and `YES` or `No` for calibration |
| 4.3 | Track calibration status correct | 1. Calibrate exactly 2 tracks<br>2. Open Manifest | Only the 2 calibrated tracks show `YES` in the Cal column; all others show `No` |
| 4.4 | Manifest updates after calibration | 1. Open Manifest (no tracks calibrated yet)<br>2. All show `No`<br>3. Calibrate 1 track, re-open Manifest | That track now shows `YES` |
| 4.5 | Toggle hides Manifest | 1. Manifest visible<br>2. Click **Show Manifest** again | Manifest panel hidden. Button label unchanged |
| 4.6 | Manifest scrollable with many tracks | 1. Create 30+ tracks in REAPER<br>2. Scan, open Manifest | Manifest child window scrolls; all 30+ tracks listed within the 200px height limit |

---

## 5. GUI: Overflow Settings

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 5.1 | Radio button: New Track mode | 1. Click **New Track** radio button in the OVERFLOW section<br>2. Scan and import with multiple stems matching the same track | `overflow_mode` saved as "new_track". Second+ stems create new tracks instead of lanes |
| 5.2 | Radio button: Lanes mode | 1. Click **Lanes** radio button<br>2. Scan and import with multiple stems matching the same track | `overflow_mode` saved as "lanes". Second+ stems placed on lanes |
| 5.3 | Max lanes input accepts values | 1. In **Max:** input, type `4`<br>2. Click away or press Enter | Value saved to ExtState. Overflow respects cap: lane 5+ creates new tracks |
| 5.4 | Max lanes zero = unlimited | 1. Set **Max:** to `0`<br>2. Import 10 stems matching 1 track in lanes mode | All 10 stems placed on lanes, no cap |
| 5.5 | Per-category overflow via route_map.json | 1. Ensure `route_map.json` has `categories.sub_bass.overflow_behavior = "new_track"` while global overflow is "lanes"<br>2. Import 3 sub_bass stems against 1 sub_bass track | First stem on track, stems 2+ on new tracks below (category override wins) |
| 5.6 | Lanes cap reached creates new track | 1. Set Max=2, Lanes mode<br>2. Import 3 stems matching 1 track | Stems 1-2 on main track (lanes), stem 3 on newly created "OrigTrack - Stem3" track |
| 5.7 | Overflow settings persist across sessions | 1. Set New Track + Max=3<br>2. Close and re-open GUI | Settings restored from ExtState |

---

## 6. AI Layer — OpenAI

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 6.1 | Provider set to "openai" | 1. In AI ASSISTANT section, select "openai" from provider dropdown<br>2. Verify the Model field | Model defaults to "gpt-4o-mini" (or shows previous custom value). API URL auto-fills to `https://api.openai.com/v1` |
| 6.2 | Valid API key entered | 1. Enter a valid OpenAI API key in the **API Key** field (masked with dots)<br>2. Confirm input is masked | Key stored in ExtState. Field displays `********` (masked length). Key persisted after GUI restart |
| 6.3 | Custom model works | 1. Change Model field to `gpt-4o`<br>2. Scan a folder that produces orphans | The `_ai_request.json` contains `"model": "gpt-4o"` in the payload |
| 6.4 | Scan with orphans triggers curl | 1. Set OpenAI provider, valid API key, `gpt-4o-mini` model<br>2. Scan a folder with 2+ orphan stems<br>3. Observe LOG | LOG shows "AI: consulting gpt-4o-mini via openai..." Request posted to `https://api.openai.com/v1/chat/completions` |
| 6.5 | mapping.json written | 1. After AI scan completes successfully<br>2. Check script directory | `mapping.json` exists with `{"assignments": {"Cowbell.wav": "Percussion", ...}, "status": "success"}` |
| 6.6 | Import uses AI assignments | 1. Scan with AI producing a mapping.json<br>2. Click **IMPORT STEMS** | Orphan stems inserted on the tracks the AI assigned. LOG shows "AI assigned N orphan(s)" |
| 6.7 | AI response structure verified | 1. After successful AI scan, inspect the `mapping.json` content | Valid JSON with `assignments` object mapping filenames (strings) to track names (strings) |

---

## 7. AI Layer — OpenCode

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 7.1 | Provider set to "opencode" | 1. Select "opencode" from provider dropdown<br>2. Verify changes | Model field clears (can be set manually). API URL auto-fills to `https://api.opencode.ai/v1` |
| 7.2 | Valid OpenCode API key works | 1. Enter a valid OpenCode API key<br>2. Scan folder with orphans | Request uses OpenAI-compatible format (`messages[]` array, `Authorization: Bearer <key>` header). Request posted to `https://api.opencode.ai/v1/chat/completions` |
| 7.3 | Response format matches OpenAI | 1. With OpenCode provider, scan folder with orphans<br>2. Compare with OpenAI response structure | Both use `choices[0].message.content` path in `parse_response`. JSON output format identical |
| 7.4 | Model field respected | 1. Set model to a specific OpenCode model name<br>2. Scan | `_ai_request.json` contains `"model": "<model_name>"` in the payload |

---

## 8. AI Layer — Gemini

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 8.1 | Provider set to "gemini" | 1. Select "gemini" from provider dropdown<br>2. Verify changes | Model defaults to previously stored value or empty. API URL auto-fills to `https://generativelanguage.googleapis.com/v1beta` |
| 8.2 | Gemini model works | 1. Set model to `gemini-2.0-flash` or `gemini-1.5-flash`<br>2. Enter valid Gemini API key<br>3. Scan folder with orphans | Request uses **Gemini native format** (`contents[]` array, `system_instruction`, `generationConfig`). API key sent as URL parameter: `?key=<key>` NOT as Authorization header |
| 8.3 | Gemini request structure verified | 1. After scan, open `_ai_request.json` before it is cleaned up (or check the code) | Payload has `contents[].role` and `contents[].parts[].text`, plus `system_instruction.parts[].text`, `generationConfig.response_mime_type = "application/json"` |
| 8.4 | Gemini response parsed correctly | 1. Successful Gemini API call with orphans<br>2. Check LOG after scan | LOG shows "AI: N mapping(s) resolved". The Gemini response path `candidates[0].content.parts[0].text` was used to extract the JSON mapping |
| 8.5 | No Authorization header for Gemini | 1. Inspect the curl command for Gemini provider (check code or log) | curl command has the key in the URL, NO `-H "Authorization: Bearer ..."` header |

---

## 9. AI Layer — Custom Endpoint

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 9.1 | Edit API URL to custom endpoint | 1. Select "openai" provider<br>2. Change API URL to `https://openrouter.ai/api/v1`<br>3. Enter OpenRouter API key<br>4. Scan with orphans | curl posts to `https://openrouter.ai/api/v1/chat/completions` with OpenAI-compatible format |
| 9.2 | Local LLM endpoint | 1. Set API URL to `http://localhost:1234/v1` (e.g., LM Studio / Ollama)<br>2. Set provider="openai"<br>3. Enter any dummy key (or none if local LLM doesn't require one)<br>4. Scan with orphans | curl issues request to local endpoint. If the LLM is running and responds, mapping produced |
| 9.3 | Custom endpoint with Gemini format | 1. Set provider="gemini", API URL to custom Gemini-compatible proxy<br>2. Enter API key<br>3. Scan | Request uses Gemini native format (`contents[]`, key in URL). Posted to custom URL with `:generateContent?key=<key>` |
| 9.4 | Error: endpoint unreachable | 1. Set API URL to `http://localhost:99999/v1` (non-existent server)<br>2. Scan with orphans | LOG shows "AI: curl returned nothing — check API key, URL, and network". No mapping.json produced. Import continues without AI |

---

## 10. AI Layer — Edge Cases

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 10.1 | Empty API key → AI skipped | 1. Leave API Key field empty<br>2. Scan folder with orphans | AI curl call NOT made. LOG shows the match results but no AI message. No error shown. Import proceeds normally |
| 10.2 | Empty API key with provider set | 1. Set provider to "openai" but leave key empty<br>2. Scan with orphans | Condition `state.ai_api_key ~= ""` is false; AI path skipped entirely. No error |
| 10.3 | Invalid API key → error logged | 1. Enter an obviously invalid key like "sk-bad"<br>2. Scan with orphans | API returns 401 error. `curl` may return HTML/error body. LOG shows "AI: response wasn't valid JSON: ..." or "AI: curl returned nothing". Import proceeds without AI |
| 10.4 | No orphans → AI not called | 1. Scan a folder where all stems match tracks cleanly (no orphans)<br>2. Observe LOG | Orphan count is 0. AI path not triggered. No curl call made. LOG shows "Matched: N, Orphans: 0" |
| 10.5 | Invalid JSON response from API | 1. Set up a test endpoint that returns malformed JSON<br>2. Scan with orphans | `parse_response` returns nil. LOG shows "AI: response wasn't valid JSON: [first 120 chars]". Import proceeds |
| 10.6 | API response missing assignments key | 1. API returns valid JSON but no `assignments` field, e.g. `{"foo": "bar"}`<br>2. Scan with orphans | JSON parsed OK but `mapping.assignments` is nil. mapping.json NOT written. LOG does NOT show "AI: N mapping(s) resolved" |
| 10.7 | API timeout | 1. Point to a slow endpoint<br>2. Scan with orphans | `reaper.ExecProcess` has a 120s timeout. If curl times out, stdout is empty. LOG shows "AI: curl returned nothing" |
| 10.8 | AI config persistence across restart | 1. Set provider="gemini", model="gemini-2.0-flash", enter an API key<br>2. Close and reopen REAPER + GUI | All AI fields restored: provider="gemini", model="gemini-2.0-flash", API key masked |

---

## 11. Import Pipeline

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 11.1 | Basic: scan → import | 1. Browse to folder with 3 stems that match 3 tracks<br>2. Click **Scan Folder**<br>3. Click **IMPORT STEMS** | Each stem inserted as a media item at position 0:00 on its matched REAPER track. LOG shows "3 inserted, 0 overflowed, 0 skipped" |
| 11.2 | Color inheritance | 1. Set a track color (right-click track → Track color → Set to custom color)<br>2. Ensure `route_map.json` has `color_stems_by_track: true`<br>3. Import a stem matching that track | Imported media item has the same track color applied |
| 11.3 | Undo block: single Ctrl+Z removes all | 1. Import 5+ stems<br>2. Press Ctrl+Z once | ALL imported items removed in one undo step. Original project state fully restored |
| 11.4 | Undo removes overflow tracks | 1. Import in "new_track" mode with 3 overflow stems creating 2 new tracks<br>2. Press Ctrl+Z | New overflow tracks removed along with all imported items. Single undo block |
| 11.5 | Skip stems with no track match | 1. Scan folder with 2 matchable stems + 1 orphan<br>2. Do NOT use AI (no API key)<br>3. Click **IMPORT STEMS** | 2 stems inserted. Orphan skipped. LOG shows "2 inserted, 0 overflowed, 1 skipped, 1 orphan(s)..." |
| 11.6 | Overflow: lanes mode | 1. Set overflow to Lanes, Max=0<br>2. Import 3 Fx stems against 1 Fx track | First stem at position 0:00. Stems 2-3 placed on lanes 2-3 of the same track (using Fixed Lanes API if available) |
| 11.7 | Overflow: new_track mode | 1. Set overflow to New Track<br>2. Import 3 percussion stems against 1 Percussion track | First stem on Percussion. Stem 2 on "Percussion - Stem2", Stem 3 on "Percussion - Stem3" |
| 11.8 | Overflow respects per-category new_track | 1. route_map.json: `categories.drums.overflow_behavior = "new_track"`<br>2. Global overflow = Lanes<br>3. Import 3 drum stems | Drums use new_track (not lanes). Second+ stems create new tracks |
| 11.9 | Import button disabled before scan | 1. Open fresh GUI (no scan yet)<br>2. Observe the IMPORT STEMS button | Button is replaced by text "[Scan a folder to enable import]" or disabled |

---

## 12. Scoring & Matching Edge Cases

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 12.1 | Full token match | 1. File: `Lead Vocal.wav`, Track: "Vocals Lead"<br>2. Run scan | Both share token "lead" and "vocal" → `lead→melody, vocal→vocals`. If alias resolution creates overlap, match. Otherwise token-intersection score computed correctly |
| 12.2 | Subset match | 1. File: `Kick Sub.wav`, Track: "Kick"<br>2. Run scan | Tokens: "kick" and "sub". Track "Kick" has token "kick". Shared=1, min(2,1)=1 → score=1.0 → matched via token-intersection |
| 12.3 | Typo correction (fuzzy) | 1. File: `Kicck_01.wav`, Track: "Kick"<br>2. Ensure `fuzzy_threshold = 0.8` in route_map.json<br>3. Run scan | Token-intersection fails (no shared tokens). Fuzzy fallback: Levenshtein distance between "kicck" and "kick" = 1, max_len=5, score=0.8 → match via "fuzzy" |
| 12.4 | No match → orphan | 1. File: `Theremin_Solo.wav`, Track: "Kick"<br>2. No alias for "theremin" or "solo"<br>3. Run scan | Token-intersection score 0, fuzzy score below threshold, no alias. File listed as orphan with reason "no match in any track" |
| 12.5 | Calibrated track preferred over name match | 1. Calibrate track "Kick Main" (not "Kick")<br>2. File: `Kick_01.wav`<br>3. Run scan | Even if "Kick" track exists, calibrated "Kick Main" wins via calibrated priority chain (calibrated threshold 0.2 < shared tokens) |
| 12.6 | Alias resolution with ignore keywords | 1. File: `808_Bass_Mix_Master.wav`<br>2. Track: "sub_bass"<br>3. Default route_map.json | "mix", "master" stripped. Tokens: "808" → "sub_bass", "bass" → "sub_bass". Score 1.0 against "sub_bass" track |
| 12.7 | Pure numbers stripped | 1. File: `Kick_01_v2.wav`<br>2. Track: "Kick"<br>3. Default config | "01", "v2" stripped (keywords_ignore). Token: "kick". Score 1.0 vs "Kick". Match via token-intersection |
| 12.8 | Empty stem name after tokenization | 1. File: `01_02_03.wav`<br>2. Default config | All tokens are numbers or ignored kw; token list empty. Returns nil (orphan) |

---

## 13. route_map.json Edge Cases

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 13.1 | Missing file → built-in defaults | 1. Delete or rename `route_map.json`<br>2. Run scan | Console: "Grove: /path/route_map.json not found. Using built-in defaults." Script works with empty defaults (no aliases, lanes mode, max_lanes=0) |
| 13.2 | Invalid JSON → error logged, uses defaults | 1. Write `{ broken: yes }` to `route_map.json`<br>2. Run scan | Console: "Grove: JSON error in ... Using defaults." Script continues with default config |
| 13.3 | Empty file → uses defaults | 1. Truncate `route_map.json` to empty<br>2. Run scan | Console: "Grove: ... is empty. Using built-in defaults." |
| 13.4 | Missing optional v2 keys → defaults filled | 1. `route_map.json` with only `alias`, `keywords_ignore`, `overflow_behavior`, `max_lanes_per_track`<br>2. Run scan | Missing keys (`fuzzy_threshold`, `alias_priority`, `lanes_mode`, `color_stems_by_track`, `ai_config`) populated from defaults |
| 13.5 | Schema validation catches bad values | 1. Set `overflow_behavior: "invalid_value"` in route_map.json<br>2. Run scan | Console: "Grove: Schema error in ... 'overflow_behavior' must be \"lanes\" or \"new_track\". Using defaults." |
| 13.6 | Schema: fuzzy_threshold out of range | 1. Set `"fuzzy_threshold": 1.5`<br>2. Run scan | Console: "'fuzzy_threshold' must be a number between 0 and 1". Uses defaults |
| 13.7 | Categories fully absent from JSON | 1. route_map.json has all v2 keys but no `categories`<br>2. Run scan | Defaults provide empty `categories = {}`. No per-category overrides. Global overflow_behavior used for all |
| 13.8 | ExtState restores folder and prefs | 1. Set a folder path, overflow=lanes, max_lanes=3, and AI fields<br>2. Close and re-open GUI | All values restored: folder path, overflow mode, max lanes, AI provider, model, API URL, API key (masked), recent GUIDs |

---

## 14. Legacy Python Proxy

| # | Scenario | Steps | Expected Result |
|---|----------|-------|-----------------|
| 14.1 | Python proxy can be used as alternative | 1. Ensure Python 3 is installed<br>2. Navigate to `ai-proxy/` directory<br>3. Run `python main.py` with valid API config | Proxy reads `orphans.json` and `ai_config.json` written by scan_folder(), queries the LLM, and writes `mapping.json` — same contract as the curl layer |
| 14.2 | Both curl and proxy coexist | 1. Use curl AI (GUI) for one session<br>2. Use Python proxy for another session | Both use the same `orphans.json` → `mapping.json` pipeline. No conflict. Curl layer is the **default**; Python proxy is the **legacy** alternative |
| 14.3 | Marked as LEGACY | 1. Read `openspec/specs/ai-curl-layer/spec.md` | Clear statement: "Legacy: `ai-proxy/main.py` (Python) — kept for advanced users who prefer it" |
| 14.4 | Python proxy requires pip deps | 1. Check `ai-proxy/requirements.txt` or install script | Requires `requests` (or equivalent) Python package. Not auto-installed by the REAPER script |

---

## Test Log Template

```
Date: ________
REAPER version: ________
Script version: ________
curl version (curl --version): ________

Scenarios run: ____ / ____
PASS: ____
FAIL: ____
Blocked: ____

Notes:
______________________________________________
```
