# Scripts README

This skill intentionally keeps scripts minimal and secret-safe.

## Key Loading Order

`claude` (wrapper), `claude-route`, and `healthcheck.sh` all load the gateway
key through `load_gateway_env.sh`, first hit wins:

1. an already-set `AMD_LLM_GATEWAY_KEY` in the environment
2. `${CLAUDE_AMD_ENV_FILE}` if set
3. `~/.config/claude-amd/env` (preferred dedicated secret file)
4. `~/.bashrc` (legacy fallback)

The dedicated env file avoids the Debian/Ubuntu `~/.bashrc` interactive guard
(`[ -z "$PS1" ] && return`), which otherwise hides exports placed after it from
non-interactive wrappers.

## Included Scripts

### `healthcheck.sh`

Purpose:
- confirms `claude` is on `PATH`
- confirms `claude-route` is available for route inspection
- confirms `AMD_LLM_GATEWAY_KEY` is present without printing its value
- confirms `~/.claude/settings.json` exists
- confirms the normalized direct model is supported in direct-only mode
- confirms the resolved effort is `medium` (default) or `max`, never Claude Code's `high` default

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
  "configured_model": "claude-opus-5",
  "normalized_model": "claude-opus-5",
  "effort": "medium",
  ...
}
```

The script exits non-zero if any required item is missing.

If `~/.claude/settings.json` is invalid JSON, `claude-route` will expose `settings_parse_error` and `healthcheck.sh` will fail until the wrapper repairs the file on the next `claude` launch.

If `claude-route` already resolves to `claude-opus-5` but `/model` shows an older label or does not list Opus 5 at all, the problem is the native Claude Code build's bundled model registry, not the wrapper. Check `claude --version`, run `claude update`, relaunch the interactive session, and keep `/usr/local/bin/claude` ahead of `~/.local/bin` on `PATH`. Direct calls still route correctly in the meantime because the wrapper passes `--model claude-opus-5` explicitly.

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
- use both checks together when you must prove the direct route is active and the resolved model is either `claude-sonnet-5` or `claude-opus-5`

### `claude_amd_common.py`

Shared helper for the wrappers. Responsibilities:
- defines the supported selections: `claude-sonnet-5`, `claude-opus-5` (default), and `claude-opus-5-max`
- normalizes/repairs persisted aliases (e.g. `opus[1m]`, the retired `claude-opus-4-8`) back to a supported selection
- pins non-max selections to reasoning `--effort medium` instead of Claude Code's built-in `high` default
- resolves the local `claude-opus-5-max` alias to the real model `claude-opus-5` plus reasoning `--effort max`
- emits route state for `claude-route` and the normalized `settings.json` for the wrapper

Modes: `--route`, `--ensure-settings`, `--resolve`.

### `claude-wrapper.sh` (installed as `/usr/local/bin/claude`)

Direct-only entrypoint. It loads the gateway key, forces `ANTHROPIC_BASE_URL`,
sets the `Ocp-Apim-Subscription-Key` custom header from
`AMD_LLM_GATEWAY_SUBSCRIPTION_KEY`, normalizes `settings.json`, and launches the
native Claude Code binary with an explicit `--model <real_model>` and `--effort`
(`medium` normally, `max` for the `-max` selection). It skips the injection for
any flag the caller already supplied, and treats a set `CLAUDE_CODE_EFFORT_LEVEL`
as a caller-chosen effort.

### `claude-route.sh` (installed as `/usr/local/bin/claude-route`)

Prints the resolved direct route as JSON (`mode`, `backend`, `configured_model`,
`normalized_model`, `selection`, `effort`).

### `load_gateway_env.sh` (installed alongside the wrappers)

Sourceable helper that loads `AMD_LLM_GATEWAY_KEY` (and the optional
`AMD_LLM_GATEWAY_SUBSCRIPTION_KEY`) using the lookup order above. The wrapper and
`claude-route` source it from their own directory; keep it next to them in
`/usr/local/bin`.

### `install_native.sh`

Installs the native Claude Code binary into
`~/.local/share/claude/versions/<version>` and links `~/.local/bin/claude`.

- tries the official installer first, with a timeout, so a stalled ~240MB
  download cannot hang forever
- `--seed PATH` copies an existing same-OS/arch binary instead of downloading,
  which is the reliable path inside throttled containers
- `PATH` may be a version file or a directory of version files (newest is used)

Container example:

```bash
docker cp ~/.local/share/claude/versions/<ver> <ctr>:/tmp/claude-seed
docker exec <ctr> bash -lc 'install_native.sh --seed /tmp/claude-seed'
```

## Conventions

- Never print the actual gateway key.
- Keep scripts deterministic and local-only.
- No secrets in the repository: keys live in user-local files (e.g. `~/.bashrc`) and are read from the environment.
- Prefer clear failure messages over silent fallback.
