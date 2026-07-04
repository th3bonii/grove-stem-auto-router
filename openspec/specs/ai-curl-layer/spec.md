# AI Curl Layer Specification

## Purpose

Resolve orphan stems that failed all automated matching paths by querying an LLM directly via curl from Lua — zero external dependencies beyond curl (built-in on all modern OS). Supports multiple LLM providers with different API formats.

## Requirements

### Requirement: Direct Curl Integration

The system MUST call the LLM provider API directly from Lua using `reaper.ExecProcess(cmd)` with a curl command, bypassing any Python middleware.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Curl calls provider | orphan stems exist, API key configured | scan_folder() runs | curl POST issued to provider endpoint |
| Response parsed | API returns valid JSON | parse_response() runs | assignments extracted |
| Mapping written | valid assignments returned | after parsing | mapping.json written to script directory |

### Requirement: Multi-Provider Support

The system MUST support at least three providers with different API formats.

| Provider | Format | Auth | Endpoint |
|----------|--------|------|----------|
| **openai** | OpenAI-compatible JSON payload | `Authorization: Bearer <key>` header | `{base_url}/chat/completions` |
| **opencode** | OpenAI-compatible (same format) | `Authorization: Bearer <key>` header | `{base_url}/chat/completions` |
| **gemini** | Gemini native `contents[]` array | Key in URL as `?key=<key>` | `{base_url}/models/{model}:generateContent?key=<key>` |

- GIVEN provider = "gemini"
- WHEN request is built
- THEN format uses `contents`, `system_instruction`, and `response_mime_type = "application/json"`
- AND API key sent as URL query parameter, NOT as Authorization header

- GIVEN provider = "openai" or "opencode"
- WHEN request is built
- THEN format uses standard `messages[]` array with `response_format = { type = "json_object" }`
- AND API key sent as `Authorization: Bearer <key>` header

### Requirement: Response Parsing

The system MUST parse provider-specific response structures to extract the LLM's JSON content.

- GIVEN OpenAI response with `choices[0].message.content`
- WHEN parse_response runs
- THEN extracted text is JSON-parsed for `assignments`

- GIVEN Gemini response with `candidates[0].content.parts[0].text`
- WHEN parse_response runs
- THEN extracted text is JSON-parsed for `assignments`

- GIVEN API error response (e.g., 401, 429)
- WHEN parse_response runs
- THEN error logged to console, no mapping produced

### Requirement: Request Construction

The system MUST build the LLM request as a JSON file (`_ai_request.json`) and POST it via curl's `-d @file` syntax to avoid shell escaping issues.

- GIVEN 5 orphan stems and 8 available tracks
- WHEN request is built
- THEN `_ai_request.json` contains the provider-specific payload with stem names and track names
- THEN curl command is: `curl -s <url> -H "Content-Type: application/json" <auth_header> -d @<tmp_path>`

### Requirement: Graceful Degradation

The system MUST NOT block the import pipeline if AI is unavailable or fails.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| No API key | orphan_data exists, ai_api_key is empty | scan_folder() runs | AI curl call skipped, no error |
| Curl returns empty | API unreachable | scan_folder() runs | "curl returned nothing" logged, import continues |
| Invalid JSON response | API returns malformed data | parse_response returns nil | "response wasn't valid JSON" logged, import continues |

### Requirement: Config Persistence

Provider configuration MUST persist across REAPER sessions via ExtState.

- GIVEN user sets provider to "gemini" and enters an API key
- WHEN REAPER is restarted and script runs
- THEN ai_provider, ai_model, ai_api_key, ai_api_url are restored from ExtState

### Requirement: Editable API URL

The API base URL MUST be user-editable in the GUI for custom endpoints (self-hosted LLMs, OpenRouter, etc.), with sensible defaults per provider.

- GIVEN state.ai_api_url is empty
- WHEN provider defaults are computed
- THEN openai → "https://api.openai.com/v1"
- AND opencode → "https://api.opencode.ai/v1"
- AND gemini → "https://generativelanguage.googleapis.com/v1beta"

### Requirement: GUI Integration

The AI settings panel MUST include:
- Provider dropdown (openai, opencode, gemini)
- Model name text input
- API key field (masked with `ImGui_InputTextFlags_Password`)
- API URL text input

## Data Flow

```
scan_folder()
  ├─ R.Import.scan() ──────→ stems[]
  ├─ run_matching() ────────→ assignments[]
  ├─ R.Orphan.collect() ────→ orphan_data
  │
  ├─ orphan_count > 0 AND api_key ≠ "" ?
  │   │
  │   ├─ Build request JSON → _ai_request.json
  │   ├─ curl POST → response
  │   ├─ parse_response()
  │   └─ Write → mapping.json
  │
  └─ do_import()
       └─ R.Orphan.check_ai_mapping() → apply AI assignments
```

## Provider-Specific Details

### Gemini
```lua
local gemini_req = {
    contents = { { role = "user", parts = { { text = user_prompt } } } },
    system_instruction = { parts = { { text = system_prompt } } },
    generationConfig = {
        response_mime_type = "application/json",
        temperature = 0.1,
    },
}
-- curl format: POST {base}/models/{model}:generateContent?key={api_key}
```

### OpenAI / OpenCode
```lua
local oai_req = {
    model = model,
    messages = {
        { role = "system", content = system_prompt },
        { role = "user",   content = user_prompt },
    },
    temperature = 0.1,
    response_format = { type = "json_object" },
}
-- curl format: POST {base}/chat/completions
-- Header: Authorization: Bearer {api_key}
```

## Dependencies

- **Required**: curl (built-in on macOS, Linux, Windows 10+/11)
- **None**: Python, pip, npm, or any package manager
- **Legacy**: `ai-proxy/main.py` (Python) — kept for advanced users who prefer it
