# Claude Direct-Only Model Selection Design

## Goal

Make local Claude Code setup use only the AMD Anthropic direct endpoint, default to `claude-sonnet-4.6`, allow switching to `claude-opus-4.6` through `~/.claude/settings.json`, and prevent incompatible `/model` writes such as `opus[1m]` from breaking future direct sessions.

## Problem

The current direct path is viable, but Claude Code persists interactive `/model` choices into `~/.claude/settings.json`. Some persisted values, especially `1m` aliases like `opus[1m]` or `claude-opus-4.5[1m]`, are not accepted by AMD's Anthropic-compatible endpoint and cause `400 BadRequest` responses for both interactive and `-p` usage.

This makes the setup appear flaky even though direct calls with exact model names like `claude-sonnet-4.6` and `claude-opus-4.6` work correctly.

## Design

### Direct-only local behavior

- `claude` always targets `https://llm-api.amd.com/Anthropic`
- proxy entrypoints and proxy documentation are removed from the supported flow
- verification focuses on direct route plus resolved model output

### Supported direct models

- default configured model: `claude-sonnet-4.6`
- supported high-tier model: `claude-opus-4.6`
- `sonnet` and `opus` aliases are normalized to these exact names before launch
- unsupported or legacy persisted values are rewritten to supported direct values before launching Claude Code

### Settings normalization

Before each direct launch, the wrapper reads `~/.claude/settings.json` and rewrites the `model` field as needed:

- missing model -> `claude-sonnet-4.6`
- `sonnet` -> `claude-sonnet-4.6`
- `opus` -> `claude-opus-4.6`
- `claude-sonnet-4.5`, `claude-sonnet-4.5[1m]`, `sonnet[1m]` -> `claude-sonnet-4.6`
- `claude-opus-4.5`, `claude-opus-4.5[1m]`, `opus[1m]` -> `claude-opus-4.6`
- any other unsupported or unknown value -> `claude-sonnet-4.6`

If `settings.json` itself is invalid JSON, the wrapper should preserve the broken file by writing a timestamped backup before recreating a minimal valid file with `apiKeyHelper` and a supported direct model.

This does not prevent the current interactive session from writing a bad value after startup, but it guarantees the next `claude` launch self-heals back to a supported direct model.

### Verification behavior

Verification must distinguish between:

- route correctness: direct AMD Anthropic endpoint is active
- request success: Claude call actually succeeded
- model correctness: successful result reports `claude-*`, specifically the intended 4.6 model

`verify_output_model.py` should therefore fail differently for API-error JSON versus missing model data in an otherwise successful payload.

`healthcheck.sh` should also show the configured model from `settings.json`, fail if the settings file is invalid JSON, and validate that the normalized model is inside the supported direct-only set.

## File Responsibilities

- `/usr/local/bin/claude`
  - direct-only wrapper, default model env, settings normalization, compatibility env
- `/usr/local/bin/claude-route`
  - reports direct route plus configured model state for diagnostics
- `~/.claude/settings.json`
  - stores the single source of truth for selected direct model
- `cursor_skill/.cursor/skills/claude-code-amd-setup/SKILL.md`
  - direct-only setup instructions and troubleshooting guidance
- `cursor_skill/.cursor/skills/claude-code-amd-setup/examples.md`
  - direct-only examples
- `cursor_skill/.cursor/skills/claude-code-amd-setup/scripts/healthcheck.sh`
  - direct-only healthcheck with model reporting
- `cursor_skill/.cursor/skills/claude-code-amd-setup/scripts/verify_output_model.py`
  - verification helper with explicit API-error handling

## Error Handling

- missing `AMD_LLM_GATEWAY_KEY`: fail clearly before launch
- unsupported persisted model: rewrite to supported direct model
- direct API failure: surface actual API error, not a misleading "missing modelUsage" message

## Testing

Required verification after implementation:

1. `settings.json` absent or missing `model` -> direct `claude -p` succeeds and reports `claude-sonnet-4.6`
2. `settings.json` set to `opus[1m]` -> next direct `claude -p` succeeds and reports `claude-opus-4.6`
3. `settings.json` set to `claude-opus-4.6` -> direct `claude -p` succeeds and reports `claude-opus-4.6`
4. direct Bash tool use works with normalized `claude-sonnet-4.6`
5. `claude-route` reports direct mode and current configured model
6. skill validation passes for the updated direct-only skill files
