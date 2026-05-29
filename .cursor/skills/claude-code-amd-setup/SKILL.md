---
name: claude-code-amd-setup
description: Use when setting up or repairing Claude Code against the AMD LLM Gateway, keeping the gateway key out of git, prompting the user for their own AMD_LLM_GATEWAY_KEY before local setup, or fixing a /model picker that shows a stale Opus version.
---

# Claude Code AMD Setup

Route Claude Code straight to the AMD LLM Gateway's Anthropic endpoint, defaulting to
`claude-opus-4-8` at `max` effort. The entire setup is **one wrapper script + one settings
file**. There is nothing else to maintain.

## Non-negotiable

- Never commit or print a real gateway key. Repo files use the `PASTE_YOUR_KEY_HERE` placeholder only.
- Ask the user for `AMD_LLM_GATEWAY_KEY` before writing any secret-bearing local file. If they decline, give placeholder-only steps.
- Keep the key in `~/.bashrc` (user-local) — never in the repo or in `settings.json`.
- Verify `claude -p` actually returns before claiming success.

## Upgrading the model — the only thing that normally changes

Edit **one line** in `scripts/claude` (and in the installed `/usr/local/bin/claude`):

```bash
SUPPORTED_OPUS="claude-opus-4-8"   # bump to the new Opus id, e.g. claude-opus-4-9
```

Re-copy the wrapper to `/usr/local/bin/claude`, open a new shell, done. The `opus` alias,
the picker's Default option, and the capability flags all follow this line automatically.

## First-time setup

1. Put the key in `~/.bashrc` (ask the user for the value first):

```bash
export AMD_LLM_GATEWAY_KEY="PASTE_YOUR_KEY_HERE"
```

2. Install the wrapper as the `claude` entrypoint. It must sit ahead of any
   `~/.local/bin/claude` on `PATH`, so `/usr/local/bin` is the right place:

```bash
sudo cp .cursor/skills/claude-code-amd-setup/scripts/claude /usr/local/bin/claude
sudo chmod +x /usr/local/bin/claude
```

3. Create `~/.claude/settings.json`:

```json
{
  "apiKeyHelper": "echo amd-gateway-placeholder",
  "model": "claude-opus-4-8",
  "availableModels": ["opus"]
}
```

The native CLI must be new enough to know `claude-opus-4-8` and the `max` / `xhigh` effort
capabilities — install/upgrade with `npm i -g @anthropic-ai/claude-code` (2.1.156+).

## What the wrapper does

`scripts/claude` is the only moving part. On each launch it:

- forces the direct AMD Anthropic endpoint (`ANTHROPIC_BASE_URL` + the `Ocp-Apim-Subscription-Key` header) — no proxy;
- sets a single dummy `ANTHROPIC_AUTH_TOKEN` to skip the login prompt (two dummy creds trigger an "Auth conflict" warning, so keep only one);
- pins the `opus` alias and the picker's Default option to `SUPPORTED_OPUS` and declares its capabilities, so effort levels and adaptive thinking work and the menu stops showing a stale Opus version;
- defaults effort to `max` via `CLAUDE_CODE_EFFORT_LEVEL` (this cannot be persisted any other way);
- normalizes a bad persisted model in `settings.json` (e.g. an `opus[1m]` left behind by `/model`) back to a supported id.

It is kept (not inlined into `.bashrc`) because the native binary is invoked through it and
the startup repair runs there; do not bypass it by prepending `~/.local/bin` to `PATH`.

## Verify

```bash
claude -p 'Reply with exactly OK' --output-format json
```

Expect `"result": "OK"` and `claude-opus-4-8` under `modelUsage`. If it errors, read the
actual API error instead of assuming the route is fine.

## Troubleshooting

- `/model` shows an old Opus label → the native CLI is stale. Run `claude update` (or
  `npm i -g @anthropic-ai/claude-code`), then fully exit and relaunch the session.
- `400 BadRequest` on a `1m` alias → `/model` persisted an unsupported id. The wrapper
  repairs it on the next launch, or set `settings.json` `model` back to `claude-opus-4-8`.
- Wrong binary → `which claude` must be the wrapper at `/usr/local/bin/claude`, not `~/.local/bin/claude`.
- Key missing → check with `echo "${AMD_LLM_GATEWAY_KEY:+set}"`; add it to `~/.bashrc` and open a new shell.
