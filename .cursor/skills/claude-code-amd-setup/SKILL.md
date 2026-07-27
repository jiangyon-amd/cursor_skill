---
name: claude-code-amd-setup
description: Use when users want Claude Code configured for AMD LLM Gateway, need secrets kept out of git, must be prompted for their own gateway key before local setup, or report that the interactive model menu does not match the routed model.
---

# Claude Code AMD Setup

## Purpose

Provide a safe workflow for setting up Claude Code against AMD LLM Gateway without committing secrets. The preferred result is:
- `claude` always uses the direct AMD Anthropic endpoint
- `~/.claude/settings.json` is the single source of truth for model selection
- the supported selections are `claude-sonnet-5`, `claude-opus-5` (default), and `claude-opus-5-max`
- non-max selections run at an explicit reasoning `--effort medium`, because Claude Code's own per-model default is `high` and this setup deliberately does not inherit it
- `claude-opus-5-max` is a local alias that runs `claude-opus-5` with reasoning `--effort max` (the gateway has no separate `-max` deployment)
- startup logic repairs persisted `/model` aliases such as `opus[1m]` or retired models like `claude-opus-4-8` back to supported selections
- if `/model` labels look older than `claude-route`, update the native Claude Code build and restart the session instead of changing wrapper precedence

## When to Use

- user asks to install, configure, or repair Claude Code for AMD LLM Gateway
- user wants reusable setup instructions with no real API key in git
- setup must prompt for `AMD_LLM_GATEWAY_KEY` instead of hard-coding it
- direct mode must stay simple and must not depend on a local proxy

## Non-Negotiable Rules

1. Never commit or print a real gateway key into repository files.
2. Always ask the user for `AMD_LLM_GATEWAY_KEY` before writing secret-bearing local config.
3. If the user does not provide the key, stop automatic setup and switch to placeholder-based manual steps.
4. Keep secrets in user-local files such as `~/.bashrc`, not in the repository.
5. Use the direct AMD Anthropic endpoint only. Do not add or restore proxy fallback.
6. Default `claude` to `claude-opus-5`. Do not use retired models such as `claude-opus-4-8` or `claude-opus-4-7`.
7. Keep `claude-sonnet-5` as the supported lower-cost direct model.
8. Never let the default selection run at `high` effort. Non-max selections must pass an explicit `--effort medium` rather than inheriting Claude Code's built-in `high` default.
9. Treat `~/.claude/settings.json` as the supported model switch location.
10. Verify `claude -p` works before claiming setup is complete.
11. Never infer success from route alone. Verify the successful result model too.

## Preferred Local Layout

Use this minimal pattern when creating or repairing the local setup:

- `~/.config/claude-amd/env` (preferred secret location)
  - stores `export AMD_LLM_GATEWAY_KEY="PASTE_YOUR_KEY_HERE"` and, behind APIM, `export AMD_LLM_GATEWAY_SUBSCRIPTION_KEY="..."`
  - has no interactive guard, so the wrapper always loads it non-interactively
  - `chmod 600` it
- `~/.bashrc` (optional, interactive convenience only)
  - may also export the key, but it MUST be placed ABOVE the interactive guard (`[ -z "$PS1" ] && return`); exports after the guard are invisible to the non-interactive wrapper
  - if `~/.local/bin` is added for the native Claude Code install, keep it after system paths so `/usr/local/bin/claude` stays first
- `~/.claude/settings.json`
  - stores `apiKeyHelper` plus the selected direct model
- `/usr/local/bin/claude`
  - wrapper that forces direct AMD Anthropic mode, enables compatibility settings, and normalizes unsupported model aliases to supported direct models
- `/usr/local/bin/claude-route`
  - route inspector that reports direct route plus configured and normalized model state
- `/usr/local/bin/claude-selfupdate`
  - version scanner and updater for the native build; the built-in `claude update` cannot see releases while the wrapper disables nonessential traffic
- `/usr/local/bin/claude_amd_common.py` and `/usr/local/bin/load_gateway_env.sh`
  - helper modules the wrapper and route inspector load from their own directory

## Robust Key Loading

The wrapper and `claude-route` must obtain `AMD_LLM_GATEWAY_KEY` even when invoked
non-interactively (for example `claude -p ...`, CI, or `docker exec`). They load
it via `load_gateway_env.sh` in this order, first hit wins:

1. an already-set `AMD_LLM_GATEWAY_KEY` in the environment
2. `${CLAUDE_AMD_ENV_FILE}` if set
3. `~/.config/claude-amd/env`
4. `~/.bashrc` (legacy fallback)

Critical gotcha: the default `~/.bashrc` on Debian/Ubuntu begins with an
interactive guard such as `[ -z "$PS1" ] && return` (or a `case $- in *i*)`
form). When sourced non-interactively this guard returns immediately, so any
`export AMD_LLM_GATEWAY_KEY=...` placed AFTER it is never seen and the wrapper
fails with "AMD_LLM_GATEWAY_KEY is not set" even though the line exists in the
file. Two safe fixes:

- preferred: put the exports in `~/.config/claude-amd/env` (no guard), and
- if you must use `~/.bashrc`, place the exports ABOVE the interactive guard.

`load_gateway_env.sh` also pre-sets `PS1` before sourcing, so the legacy
`~/.bashrc` fallback still works when exports are kept above the guard.

## Container / Pod and Multi-User Setup

The same direct-mode design works inside a Docker container or pod, with a few
extra considerations:

- Native binary download is the main friction. The native Claude Code binary is
  large (~240MB) and `curl https://claude.ai/install.sh | bash` can stall or
  time out on throttled container networks. Prefer seeding from an existing
  same-OS/arch install instead of downloading again:
  - `docker cp ~/.local/share/claude/versions/<ver> <ctr>:/tmp/claude-seed`
  - then inside the container: `install_native.sh --seed /tmp/claude-seed`
  - `install_native.sh` also tries the official installer first (with a timeout)
    and only falls back to guidance if it stalls.
- The wrapper at `/usr/local/bin/claude` is global and shared by all users; it
  calls `"${HOME}/.local/bin/claude"`, so it automatically resolves to each
  user's own native binary.
- Per-user state is keyed on `$HOME`. Each user that should run `claude` needs:
  its own native binary at `~/.local/bin/claude`, its key reachable via the
  loading order above (ideally `~/.config/claude-amd/env`), and its own
  `~/.claude/settings.json`. Configuring `root` does not configure other users.
- Keep `/usr/local/bin` ahead of `~/.local/bin` on `PATH` so the wrapper, not
  the raw native binary, is the entrypoint. A safe `export PATH=/usr/local/bin:$PATH`
  can be placed above the interactive guard in each user's `~/.bashrc`.
- Persistence: edits made in a running container live in its writable layer and
  are lost on `docker rm`. For durable setup, bake the steps into the image
  (Dockerfile) or mount a volume; treat keys as secrets either way.
- The native binary may auto-update in the background, so the running CLI
  version can be newer than the one you seeded. Trust `claude --version` and
  `claude-route` over the seed version.

## Interaction Flow

### Step 1: Inspect current state

Check the current machine without leaking secrets:

- `claude --version`
- `claude-route`
- `claude-selfupdate --check` to see whether the native build is behind
- `which claude`
- `readlink -f "$HOME/.local/bin/claude"` when that path exists
- `echo "${AMD_LLM_GATEWAY_KEY:+set}"`
- check the key source: `ls -l "$HOME/.config/claude-amd/env"` and, if relying on `~/.bashrc`, confirm the export sits above the interactive guard
- `bash ".cursor/skills/claude-code-amd-setup/scripts/healthcheck.sh"` when available and run from the repository root

Do not echo the actual key value.

### Step 2: Ask for the key if needed

If `AMD_LLM_GATEWAY_KEY` is missing, say so directly and ask the user to provide it.

Required behavior:
- ask for the key before editing secret-bearing files
- explain that the repository will keep only placeholders
- offer placeholder-only manual guidance if the user does not want to share the key

### Step 3: Choose setup path

#### Path A: User provides key

Proceed with automatic local setup:

1. write the key to `~/.config/claude-amd/env` (preferred; `chmod 600`) so non-interactive wrappers always load it; only use `~/.bashrc` if you keep the export above the interactive guard
2. if `~/.local/bin/claude` exists, keep `~/.local/bin` after system paths; do not prepend it ahead of `/usr/local/bin`. If the native binary is missing, install it with `install_native.sh` (seed from an existing install when the download stalls)
3. install or update the `claude` wrapper (plus `claude-route`, `claude_amd_common.py`, and `load_gateway_env.sh` alongside it) so it forces direct AMD Anthropic mode, defaults to `claude-opus-5` at `--effort medium`, resolves the `-max` effort alias, and normalizes unsupported persisted model aliases
4. install or update `claude-route` so users can verify the direct route, current configured model, and resolved effort
5. install `claude-selfupdate` so the native build can be kept current without `claude update` or the official installer
6. set `~/.claude/settings.json` to a supported selection, normally `claude-opus-5`
7. if `claude --version` is old or `/model` still shows stale labels such as `Opus 4.8`, run `claude-selfupdate`
8. after updating the native CLI, exit and relaunch any open interactive Claude session before trusting `/model`
9. keep repository examples placeholder-based only
10. source the shell config if needed or ask the user to open a new shell

#### Path B: User does not provide key

Do not write fake values. Instead:

1. give redacted commands using `PASTE_YOUR_KEY_HERE`
2. explain which local files the user must update
3. tell the user which verification commands to run after they set the key

## Supported Direct Models

Use only these exact selection names in `~/.claude/settings.json`:

| Selection | Real gateway model | Effort |
|---|---|---|
| `claude-sonnet-5` | `claude-sonnet-5` | `medium` |
| `claude-opus-5` (default) | `claude-opus-5` | `medium` |
| `claude-opus-5-max` | `claude-opus-5` | `max` |

Default:

```json
{
  "apiKeyHelper": "echo amd-gateway-placeholder",
  "model": "claude-opus-5"
}
```

If the user wants the lower-cost model, change `model` to `claude-sonnet-5`.
For maximum reasoning effort, change `model` to `claude-opus-5-max`.

Retired selections (`claude-opus-4-8`, `claude-opus-4-7`, `claude-sonnet-4.6`, and
their `.`/`-` and `[1m]` variants) are normalized to the current generation on the
next `claude` launch. The gateway still serves the older deployments, but this
setup does not offer them as selections.

### Why effort is pinned to `medium`

Claude Code carries a per-model `default_effort` of `high`. Inheriting that makes
every default session more expensive than intended, so the wrapper passes an
explicit `--effort medium` for non-max selections. Valid `--effort` levels are
`low`, `medium`, `high`, `xhigh`, `max`.

The wrapper only injects effort when the caller has not chosen one. It stands
down if you pass `--effort <level>` on the command line or export
`CLAUDE_CODE_EFFORT_LEVEL`, so a one-off `claude --effort xhigh` still works.

### How the `-max` selection works

The AMD gateway serves only real model names (`claude-opus-5`, `claude-sonnet-5`);
there is no `claude-opus-5-max` deployment. The wrapper therefore resolves the
`claude-opus-5-max` selection to the real model `claude-opus-5` and launches
Claude Code with `--effort max`. The wrapper always passes an explicit
`--model <real_model>` so the alias is never sent verbatim to the gateway.

## Why `/model` Can Break Direct Mode

Claude Code can persist interactive `/model` choices into `~/.claude/settings.json`. Some persisted aliases, especially `1m` variants like `opus[1m]` or `claude-opus-4-7[1m]`, are not accepted by AMD's direct Anthropic endpoint and can cause `400 BadRequest`.

Treat `/model` as unreliable for this setup. Change `~/.claude/settings.json` instead. The wrapper should repair known bad aliases on the next launch, but the clean path is still to keep the file on an exact supported model.

## Keeping the Native Build Current

Run `claude-selfupdate` to scan Anthropic's release CDN and install a newer
native build. This is the supported way to update under this setup, because the
two built-in paths both misbehave here:

- **`claude update` never sees a release.** The wrapper exports
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, and in that essential-traffic
  mode Claude Code skips its latest-version lookup entirely. The built-in
  updater suppresses the same fetches, so an AMD-wrapped install silently stops
  noticing new versions.
- **The official installer can shadow the wrapper.** `curl .../install.sh | bash`
  ends by running `claude install`, which rewrites launcher and shell
  integration and may place `~/.local/bin` ahead of `/usr/local/bin` on `PATH`.
  That would bypass the wrapper and lose direct-mode env and model normalization.

`claude-selfupdate` avoids both: it downloads the versioned binary straight from
the CDN, verifies its SHA256 against the release manifest, and only then swaps
the `~/.local/bin/claude` symlink. It touches no shell config and needs no
gateway key.

```bash
claude-selfupdate               # scan the latest channel and install if newer
claude-selfupdate --check       # report only; exit 10 when an update exists
claude-selfupdate --prune 2     # also drop old builds, keeping the newest 2
claude-selfupdate --rollback    # relink to the previously installed build
```

Behavior worth knowing:

- follows the `latest` channel by default; `--channel stable` is available, but
  note `stable` can be *older* than an installed `latest` build
- refuses to move backwards unless you pass `--allow-downgrade`, so following
  `stable` on a newer install is a no-op rather than a surprise downgrade
- verifies the checksum and smoke-tests `--version` on the new binary before
  relinking, and leaves the old build in place if either check fails
- keeps previous builds on disk (~250MB each) so `--rollback` works; pass
  `--prune N` to reclaim the space
- holds a lock directory so two concurrent runs cannot fight over the symlink
- reports whether the new build's bundled model registry knows the configured
  model, which is the check that matters after a gateway model launch

Restart any open interactive session afterwards; a running process keeps the
build it started with.

## When `/model` Does Not List Opus 5

The native Claude Code binary ships its own model registry, and a build can be
newer than its registry entry for a just-released gateway model. On such a build
`/model` will not offer Opus 5 at all, and the interactive menu tops out at the
previous generation.

This does not break the setup. Claude Code passes an unknown `--model` string
through to the endpoint, and the wrapper always supplies `--model claude-opus-5`
explicitly, so direct calls resolve correctly even when the menu does not know
the name. Confirm it with `claude-route` plus a real `claude -p --output-format json ...`
call and check the reported `modelUsage`, not the menu.

To make the menu agree, run `claude-selfupdate` and relaunch the session. Do not
rely on `claude update` here: the wrapper's essential-traffic mode stops it from
ever seeing a new release. If the build is already current and `/model` still
lacks Opus 5, the registry has simply not caught up yet — keep
`~/.claude/settings.json` on `claude-opus-5` and do not "fix" it by selecting an
older model from the menu.

## When `/model` Shows Stale Labels

`claude-route` is the source of truth for the current routed model. An older native Claude Code build can still show stale interactive labels such as `Opus 4.8` even when the wrapper and route already resolve `opus` to `claude-opus-5`.

When this happens:

- keep `/usr/local/bin/claude` first on `PATH`; do not prepend `~/.local/bin`
- check `claude --version`
- run `claude-selfupdate` to refresh the native build in `~/.local/share/claude/versions/`
- exit and relaunch the interactive Claude session, then re-check `/model`
- verify again with `claude-route` and a real `claude -p --output-format json ...` call

## Manual Fallback Snippet

Use this style for placeholder-only guidance:

```bash
# ~/.config/claude-amd/env   (preferred; then: chmod 600 ~/.config/claude-amd/env)
export AMD_LLM_GATEWAY_KEY="PASTE_YOUR_KEY_HERE"
# behind APIM, also:
export AMD_LLM_GATEWAY_SUBSCRIPTION_KEY="PASTE_YOUR_SUBSCRIPTION_KEY_HERE"
```

If you instead use `~/.bashrc`, keep these exports ABOVE the interactive guard
(`[ -z "$PS1" ] && return`), or the non-interactive wrapper will not see them.

Never replace the placeholder unless the user explicitly gives you the real key for local setup.

## Verification

Run route verification first:

```bash
claude-route
```

Expected direct-mode indicators:
- `"mode": "direct"`
- `"backend": "claude-amd-anthropic"`
- `"normalized_model": "claude-sonnet-5"` or `"claude-opus-5"`
- `"effort": "medium"` for the default selection, or `"max"` for `claude-opus-5-max`

Then run a real direct command after setup:

```bash
claude -p --output-format json 'Reply with exactly OK'
```

And confirm the JSON result still reports Claude family output:

```bash
claude -p --output-format json 'Reply with exactly OK' | \
  python3 ".cursor/skills/claude-code-amd-setup/scripts/verify_output_model.py"
```

And verify tool use still works:

```bash
claude -p --output-format json --allowedTools Bash -- \
  'Use the Bash tool to run pwd, then answer with only the absolute path.'
```

## Common Failure Modes

1. `AMD_LLM_GATEWAY_KEY` missing
   - ask the user for the key or fall back to placeholder-only guidance
2. wrong `claude` binary is used
   - check `which claude`; wrapper path should be the intended entrypoint, usually `/usr/local/bin/claude`
3. `~/.local/bin` is ahead of the wrapper in `PATH`
   - do not prepend `~/.local/bin`; the wrapper must stay first so direct-mode env and model normalization still apply
4. persisted model is a bad alias such as `opus[1m]`, or a retired one such as `claude-opus-4-8`
   - inspect `~/.claude/settings.json`; use exact supported model names only
5. direct call still fails after route check passes
   - run `claude -p --output-format json ...` and inspect the actual API error instead of only checking route state
6. `claude-route` shows `settings_parse_error`
   - launch `claude` once to let the wrapper back up and repair `~/.claude/settings.json`, then review the generated `settings.json.invalid.*` file if custom local settings must be restored
7. old shell still has stale env
   - reload the shell or open a new terminal before re-testing
8. `/model` still shows stale labels, or does not list Opus 5 at all
   - check `claude --version`; if the native CLI is old, run `claude-selfupdate` (not `claude update`, which cannot see releases in essential-traffic mode)
   - restart the interactive session after the update, then re-check `claude-route`
   - if the menu still lacks Opus 5 on a current build, its bundled model registry has not caught up; the explicit `--model claude-opus-5` from the wrapper still routes correctly, so trust `claude-route` and `modelUsage` over the menu
9. wrapper reports `AMD_LLM_GATEWAY_KEY is not set` but the export is in `~/.bashrc`
   - the export is below the interactive guard (`[ -z "$PS1" ] && return`); move it above the guard or, preferably, put it in `~/.config/claude-amd/env`
10. native install hangs or times out (common in containers)
   - the ~240MB binary download is slow/blocked; seed from an existing same-OS/arch install with `install_native.sh --seed <path>` (or `docker cp` the version file into the container first)
11. only `root` works in a container, other users get "not set" or "binary not found"
   - per-user state is keyed on `$HOME`; give each user its own `~/.local/bin/claude`, a reachable key (`~/.config/claude-amd/env`), and `~/.claude/settings.json`
12. the native build never updates itself
   - expected: the wrapper sets `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, which makes Claude Code skip its latest-version lookup, so the built-in updater goes quiet
   - run `claude-selfupdate` (or `claude-selfupdate --check` first); do not switch to the official installer, which can reorder `PATH` ahead of the wrapper
13. a new build misbehaves after `claude-selfupdate`
   - previous builds are kept in `~/.local/share/claude/versions/`; run `claude-selfupdate --rollback` to relink the prior one
14. `claude-selfupdate` reports another run holds the lock
   - a concurrent run is in progress; if none is active, remove `~/.local/share/claude/versions/.selfupdate.lock` and retry
15. `~/.local/share/claude/versions/` grows by ~250MB per build
   - run `claude-selfupdate --prune 2` to keep the current build plus one rollback target

## Validation Checklist

- [ ] no real secret added to repository files
- [ ] user was prompted for key before automatic secret-bearing edits
- [ ] key loads non-interactively (in `~/.config/claude-amd/env`, or above the `~/.bashrc` interactive guard) — verified with `claude-route` from a fresh non-interactive shell
- [ ] manual fallback uses placeholders only
- [ ] `claude-route` reports direct mode and a supported normalized direct model
- [ ] `claude-route` reports `"effort": "medium"` for the default selection, never `high`
- [ ] direct verification confirms either `claude-sonnet-5` or `claude-opus-5`
- [ ] `which claude` still points to the wrapper, not directly to `~/.local/bin/claude`
- [ ] if `/model` labels were stale, `claude --version` was checked and the session was relaunched after any native CLI update
- [ ] `claude-selfupdate --check` was run, so the user knows whether the native build is behind
- [ ] any native update went through `claude-selfupdate`, not the official installer, so `which claude` still resolves to the wrapper
- [ ] `claude -p` text call was tested
- [ ] Bash tool call was tested or any remaining limitation was stated clearly
