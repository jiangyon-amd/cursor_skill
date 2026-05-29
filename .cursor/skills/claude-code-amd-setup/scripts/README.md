# Scripts README

This skill intentionally keeps scripts minimal and secret-safe.

## Included Scripts

### `claude`

Reference implementation of the direct-mode `claude` wrapper. Install as
`/usr/local/bin/claude` and keep it ahead of any other `claude` binary on
`PATH`.

Behavior:
- loads `AMD_LLM_GATEWAY_KEY` from `~/.bashrc` even when invoked from a
  non-interactive shell (it does not source `.bashrc`, only the matching
  `export` line)
- forces direct AMD Anthropic mode by setting `ANTHROPIC_BASE_URL`,
  `ANTHROPIC_CUSTOM_HEADERS` (with `Ocp-Apim-Subscription-Key`), and a single
  dummy credential `ANTHROPIC_AUTH_TOKEN` (real auth is the Ocp-Apim header;
  setting both `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` triggers an
  "Auth conflict" startup warning)
- pins the `opus` alias and the picker's Default option to `claude-opus-4-8`
  via `ANTHROPIC_DEFAULT_OPUS_MODEL`, sets its display name, and declares its
  capabilities via `ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES` so
  effort levels and adaptive thinking are enabled for the routed id
- defaults every session to `max` effort via `CLAUDE_CODE_EFFORT_LEVEL`
- normalizes unsupported persisted model aliases in
  `~/.claude/settings.json` (e.g. `opus[1m]` -> `claude-opus-4-8`,
  anything starting with `sonnet` -> `claude-sonnet-4.6`)
- if `settings.json` is invalid JSON, backs it up as
  `settings.json.invalid.<timestamp>` and rewrites a clean default
- `exec`s the underlying native Claude Code binary at `/usr/bin/claude`

Install:

```bash
sudo install -m 0755 \
  .cursor/skills/claude-code-amd-setup/scripts/claude \
  /usr/local/bin/claude
```

### `claude-route`

Direct-mode route inspector. Install as `/usr/local/bin/claude-route`.

Output (JSON):

```json
{
  "mode": "direct",
  "backend": "claude-amd-anthropic",
  "base_url": "https://llm-api.amd.com/Anthropic",
  "configured_model": "claude-opus-4-8",
  "normalized_model": "claude-opus-4-8",
  "settings_parse_error": null
}
```

Install:

```bash
sudo install -m 0755 \
  .cursor/skills/claude-code-amd-setup/scripts/claude-route \
  /usr/local/bin/claude-route
```

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
  "configured_model": "claude-opus-4-8",
  "normalized_model": "claude-opus-4-8",
  ...
}
```

The script exits non-zero if any required item is missing.

If `~/.claude/settings.json` is invalid JSON, `claude-route` will expose `settings_parse_error` and `healthcheck.sh` will fail until the wrapper repairs the file on the next `claude` launch.

If `claude-route` already resolves to `claude-opus-4-8` but `/model` still shows older labels such as `Opus 4.6 (1M context)`, the problem is usually the native Claude Code build rather than the wrapper. Check `claude --version`, run `claude update`, relaunch the interactive session, and keep `/usr/local/bin/claude` ahead of `~/.local/bin` on `PATH`.

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
- use both checks together when you must prove the direct route is active and the resolved model is either `claude-sonnet-4.6` or `claude-opus-4-8`

## Conventions

- Never print the actual gateway key.
- Keep scripts deterministic and local-only.
- Prefer clear failure messages over silent fallback.
