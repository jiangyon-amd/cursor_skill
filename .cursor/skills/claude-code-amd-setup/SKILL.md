---
name: claude-code-amd-setup
description: Use when users want Claude Code configured for AMD LLM Gateway, need secrets kept out of git, or must be prompted for their own gateway key before local setup.
---

# Claude Code AMD Setup

## Purpose

Provide a safe workflow for setting up Claude Code against AMD LLM Gateway without committing secrets. The preferred result is:
- `claude` always uses the direct AMD Anthropic endpoint
- `~/.claude/settings.json` is the single source of truth for model selection
- the supported direct models are `claude-sonnet-4.6` and `claude-opus-4.6`
- startup logic repairs persisted `/model` aliases such as `opus[1m]` back to supported direct models

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
6. Default `claude` to `claude-sonnet-4.6`.
7. Use `claude-opus-4.6` as the supported high-tier direct model.
8. Treat `~/.claude/settings.json` as the supported model switch location.
9. Verify `claude -p` works before claiming setup is complete.
10. Never infer success from route alone. Verify the successful result model too.

## Preferred Local Layout

Use this minimal pattern when creating or repairing the local setup:

- `~/.bashrc`
  - stores only `export AMD_LLM_GATEWAY_KEY="PASTE_YOUR_KEY_HERE"`
- `~/.claude/settings.json`
  - stores `apiKeyHelper` plus the selected direct model
- `/usr/local/bin/claude`
  - wrapper that forces direct AMD Anthropic mode, enables compatibility settings, and normalizes unsupported model aliases to supported direct models
- `/usr/local/bin/claude-route`
  - route inspector that reports direct route plus configured and normalized model state

## Interaction Flow

### Step 1: Inspect current state

Check the current machine without leaking secrets:

- `claude --version`
- `claude-route`
- `which claude`
- `echo "${AMD_LLM_GATEWAY_KEY:+set}"`
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

1. update the user-local shell config to export `AMD_LLM_GATEWAY_KEY`
2. install or update the `claude` wrapper so it forces direct AMD Anthropic mode, defaults to `claude-sonnet-4.6`, and normalizes unsupported persisted model aliases
3. install or update `claude-route` so users can verify the direct route and current configured model
4. set `~/.claude/settings.json` to a supported direct model, normally `claude-sonnet-4.6`
5. keep repository examples placeholder-based only
6. source the shell config if needed or ask the user to open a new shell

#### Path B: User does not provide key

Do not write fake values. Instead:

1. give redacted commands using `PASTE_YOUR_KEY_HERE`
2. explain which local files the user must update
3. tell the user which verification commands to run after they set the key

## Supported Direct Models

Use only these exact model names in `~/.claude/settings.json`:

- `claude-sonnet-4.6`
- `claude-opus-4.6`

Default:

```json
{
  "apiKeyHelper": "echo amd-gateway-placeholder",
  "model": "claude-sonnet-4.6"
}
```

If the user wants the high-tier model, change `model` to `claude-opus-4.6`.

## Why `/model` Can Break Direct Mode

Claude Code can persist interactive `/model` choices into `~/.claude/settings.json`. Some persisted aliases, especially `1m` variants like `opus[1m]` or `claude-opus-4.5[1m]`, are not accepted by AMD's direct Anthropic endpoint and can cause `400 BadRequest`.

Treat `/model` as unreliable for this setup. Change `~/.claude/settings.json` instead. The wrapper should repair known bad aliases on the next launch, but the clean path is still to keep the file on an exact supported model.

## Manual Fallback Snippet

Use this style for placeholder-only guidance:

```bash
# ~/.bashrc
export AMD_LLM_GATEWAY_KEY="PASTE_YOUR_KEY_HERE"
```

Never replace the placeholder unless the user explicitly gives you the real key for local setup.

## Verification

Run route verification first:

```bash
claude-route
```

Expected direct-mode indicators:
- `"mode": "direct"`
- `"backend": "claude-amd-anthropic"`
- `"normalized_model": "claude-sonnet-4.6"` or `"claude-opus-4.6"`

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
   - check `which claude`; wrapper path should be the intended entrypoint
3. persisted model is a bad alias such as `opus[1m]`
   - inspect `~/.claude/settings.json`; use exact supported model names only
4. direct call still fails after route check passes
   - run `claude -p --output-format json ...` and inspect the actual API error instead of only checking route state
5. `claude-route` shows `settings_parse_error`
   - launch `claude` once to let the wrapper back up and repair `~/.claude/settings.json`, then review the generated `settings.json.invalid.*` file if custom local settings must be restored
6. old shell still has stale env
   - reload the shell or open a new terminal before re-testing

## Validation Checklist

- [ ] no real secret added to repository files
- [ ] user was prompted for key before automatic secret-bearing edits
- [ ] manual fallback uses placeholders only
- [ ] `claude-route` reports direct mode and a supported normalized 4.6 model
- [ ] direct verification confirms either `claude-sonnet-4.6` or `claude-opus-4.6`
- [ ] `claude -p` text call was tested
- [ ] Bash tool call was tested or any remaining limitation was stated clearly
