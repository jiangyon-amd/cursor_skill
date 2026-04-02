---
name: claude-code-amd-setup
description: Use when users want Claude Code configured for AMD LLM Gateway, need secrets kept out of git, or must be prompted for their own gateway key before local setup.
---

# Claude Code AMD Setup

## Purpose

Provide a safe workflow for setting up Claude Code against AMD LLM Gateway without committing secrets. This skill supports two modes:
- automatic local setup after the user provides their own key
- redacted manual guidance when the user does not want to share the key

## When to Use

- user asks to install, configure, or repair Claude Code for AMD LLM Gateway
- user wants reusable setup instructions with no real API key in git
- setup must prompt for `AMD_LLM_GATEWAY_KEY` instead of hard-coding it

## Non-Negotiable Rules

1. Never commit or print a real gateway key into repository files.
2. Always ask the user for `AMD_LLM_GATEWAY_KEY` before writing secret-bearing local config.
3. If the user does not provide the key, stop automatic setup and switch to placeholder-based manual steps.
4. Keep secrets in user-local files such as `~/.bashrc`, not in the repository.
5. Verify `claude -p` works before claiming setup is complete.
6. If AMD Anthropic `/v1/messages` is not reliable, use the local Anthropic-compatible proxy fallback instead of pretending direct setup works.

## Preferred Local Layout

Use this minimal pattern when creating or repairing the local setup:

- `~/.bashrc`
  - stores only `export AMD_LLM_GATEWAY_KEY="PASTE_YOUR_KEY_HERE"`
- `~/.claude/settings.json`
  - stores safe defaults such as `apiKeyHelper` and a default model alias
- `/usr/local/bin/claude`
  - wrapper that fills missing defaults and auto-starts the local proxy if needed
- `~/.claude/amd_gateway_proxy.py`
  - local Anthropic-compatible fallback proxy that can bridge to AMD OpenAI-compatible models when direct Anthropic generation is unavailable

## Interaction Flow

### Step 1: Inspect current state

Check the current machine without leaking secrets:

- `claude --version`
- `which claude`
- `echo "${AMD_LLM_GATEWAY_KEY:+set}"`
- `bash ".cursor/skills/claude-code-amd-setup/scripts/healthcheck.sh"` when available and run from the repository root

Do not echo the actual key value.

### Step 2: Ask for the key if needed

If `AMD_LLM_GATEWAY_KEY` is missing, say so directly and ask the user to provide it.

Required behavior:
- ask for the key before editing secret-bearing files
- explain that the repository will keep only placeholders
- offer a manual fallback if the user does not want to share the key

### Step 3: Choose setup path

#### Path A: User provides key

Proceed with automatic local setup:

1. update the user-local shell config to export `AMD_LLM_GATEWAY_KEY`
2. install or update the `claude` wrapper and local proxy files using redacted templates; note that `/usr/local/bin/claude` may require elevated permissions
3. keep repository examples placeholder-based only
4. source the shell config if needed or ask the user to open a new shell

#### Path B: User does not provide key

Do not write fake values. Instead:

1. give redacted commands using `PASTE_YOUR_KEY_HERE`
2. explain which local files the user must update
3. tell the user which verification command to run after they set the key

## Manual Fallback Snippet

Use this style for placeholder-only guidance:

```bash
# ~/.bashrc
export AMD_LLM_GATEWAY_KEY="PASTE_YOUR_KEY_HERE"
```

Never replace the placeholder unless the user explicitly gives you the real key for local setup.

## Verification

Run real commands after setup:

```bash
claude -p --output-format json 'Reply with exactly OK'
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
3. direct Anthropic generation hangs
   - switch to or preserve the local proxy fallback
4. old shell still has stale env
   - reload the shell or open a new terminal before re-testing

## Validation Checklist

- [ ] no real secret added to repository files
- [ ] user was prompted for key before automatic secret-bearing edits
- [ ] manual fallback uses placeholders only
- [ ] `claude -p` text call was tested
- [ ] Bash tool call was tested or any remaining limitation was stated clearly
