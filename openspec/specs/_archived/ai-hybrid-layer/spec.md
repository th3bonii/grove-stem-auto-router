# AI Hybrid Layer Specification

## Purpose

Provide an optional Python proxy server that receives unmatched stems via OSC, queries an LLM for semantic matching suggestions, and returns results. Degrades gracefully when Python is unavailable.

## Requirements

### Requirement: Python Proxy Server

The system MUST spawn a Python subprocess (`ai-proxy/main.py`) at script start that listens on a configurable OSC port. The Lua script MUST communicate via OSC messages.

| Scenario | GIVEN | WHEN | THEN |
|----------|-------|------|------|
| Proxy starts | Python 3.10+ available, port 9000 free | script initializes | proxy listening on port 9000 |
| Port in use | port 9000 already occupied | proxy starts | port increment attempted, console notice |

### Requirement: Graceful Degradation

If Python is not found or the proxy fails to start, the system MUST skip AI matching with a console notice. No blocking dialogs.

- GIVEN Python is not installed
- WHEN proxy startup fails
- THEN script continues without AI matching, console entry logged

### Requirement: LLM Matching Request

The system MUST send unmatched stems as JSON via OSC to the proxy, requesting semantic category suggestions.

- GIVEN 5 stems unresolved by deterministic matching
- WHEN proxy receives request
- THEN it sends a prompt to the configured LLM API with stem names

### Requirement: API Key Management

API keys MUST be stored in a `.env` file next to the proxy. The system MUST NOT embed keys in source code.

- GIVEN `.env` with `OPENAI_API_KEY=sk-...`
- WHEN proxy starts
- THEN key loaded from environment
- AND missing key logs a warning and returns empty results
