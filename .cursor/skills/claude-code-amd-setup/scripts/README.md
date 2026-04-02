# Scripts README

This skill intentionally keeps scripts minimal and secret-safe.

## Included Scripts

### `healthcheck.sh`

Purpose:
- confirms `claude` is on `PATH`
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
AMD_LLM_GATEWAY_KEY: set
settings.json: found
```

The script exits non-zero if any required item is missing.

## Conventions

- Never print the actual gateway key.
- Keep scripts deterministic and local-only.
- Prefer clear failure messages over silent fallback.
