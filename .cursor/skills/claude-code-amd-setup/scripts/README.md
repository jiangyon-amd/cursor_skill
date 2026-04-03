# Scripts README

This skill intentionally keeps scripts minimal and secret-safe.

## Included Scripts

### `healthcheck.sh`

Purpose:
- confirms `claude` is on `PATH`
- confirms `claude-route` is available for route inspection
- confirms `AMD_LLM_GATEWAY_KEY` is present without printing its value
- confirms `~/.claude/settings.json` exists

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
  ...
}
```

The script exits non-zero if any required item is missing.

### `verify_output_model.py`

Purpose:
- parses Claude Code JSON output
- fails if no model is reported
- fails if any reported model does not start with `claude-`

Usage:

```bash
claude -p --output-format json 'Reply with exactly OK' | \
  python3 ".cursor/skills/claude-code-amd-setup/scripts/verify_output_model.py"
```

Important:
- this script verifies the reported model family
- it does not replace `claude-route`
- use both checks together when you must prove the default route is real Claude direct mode rather than a proxy path

## Conventions

- Never print the actual gateway key.
- Keep scripts deterministic and local-only.
- Prefer clear failure messages over silent fallback.
