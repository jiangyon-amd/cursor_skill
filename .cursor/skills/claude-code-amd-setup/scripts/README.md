# Scripts README

This skill intentionally keeps scripts minimal and secret-safe.

## Included Scripts

### `healthcheck.sh`

Purpose:
- confirms `claude` is on `PATH`
- confirms `claude-route` is available for route inspection
- confirms `AMD_LLM_GATEWAY_KEY` is present without printing its value
- confirms `~/.claude/settings.json` exists
- confirms the normalized direct model is supported in direct-only mode

Usage:

```bash
# Run from the repository root.
bash ".cursor/skills/claude-code-amd-setup/scripts/healthcheck.sh"
```

Expected output:

```text
claude: found
claude-route: found
AMD_LLM_GATEWAY_KEY: set
settings.json: found
{
  "mode": "direct",
  "backend": "claude-amd-anthropic",
  "configured_model": "claude-sonnet-4.6",
  "normalized_model": "claude-sonnet-4.6",
  ...
}
```

The script exits non-zero if any required item is missing.

If `~/.claude/settings.json` is invalid JSON, `claude-route` will expose `settings_parse_error` and `healthcheck.sh` will fail until the wrapper repairs the file on the next `claude` launch.

### `verify_output_model.py`

Purpose:
- parses Claude Code JSON output
- fails early with the actual API error when the request itself failed
- fails if no model is reported
- fails if any reported model is outside the supported direct-only set

Usage:

```bash
claude -p --output-format json 'Reply with exactly OK' | \
  python3 ".cursor/skills/claude-code-amd-setup/scripts/verify_output_model.py"
```

Important:
- this script verifies successful output against the supported direct models
- it does not replace `claude-route`
- use both checks together when you must prove the direct route is active and the resolved model is either `claude-sonnet-4.6` or `claude-opus-4.6`

## Conventions

- Never print the actual gateway key.
- Keep scripts deterministic and local-only.
- Prefer clear failure messages over silent fallback.
