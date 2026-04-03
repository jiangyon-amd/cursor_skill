---
name: claude-code-amd-setup
description: Use when users want Claude Code configured for AMD LLM Gateway, need secrets kept out of git, or must be prompted for their own gateway key before local setup.
---

# Claude Code AMD Setup

## Purpose

Provide a safe workflow for setting up Claude Code against AMD LLM Gateway without committing secrets. The preferred result is:
- `claude` defaults to direct AMD Anthropic mode
- `claude-proxy` is available as a manual fallback
- verification proves the active route is really Claude direct mode rather than a proxy path that only looks like Claude from the model label

## When to Use

- user asks to install, configure, or repair Claude Code for AMD LLM Gateway
- user wants reusable setup instructions with no real API key in git
- setup must prompt for `AMD_LLM_GATEWAY_KEY` instead of hard-coding it

## Non-Negotiable Rules

1. Never commit or print a real gateway key into repository files.
2. Always ask the user for `AMD_LLM_GATEWAY_KEY` before writing secret-bearing local config.
3. If the user does not provide the key, stop automatic setup and switch to placeholder-based manual steps.
4. Keep secrets in user-local files such as `~/.bashrc`, not in the repository.
5. Default `claude` to direct AMD Anthropic mode when it is working.
6. Expose proxy fallback via a separate manual command such as `claude-proxy`.
7. Verify `claude -p` works before claiming setup is complete.
8. Never infer "direct Claude" from a Claude-looking model label alone. Check the route explicitly.

## Preferred Local Layout

Use this minimal pattern when creating or repairing the local setup:

- `~/.bashrc`
  - stores only `export AMD_LLM_GATEWAY_KEY="PASTE_YOUR_KEY_HERE"`
- `~/.claude/settings.json`
  - stores safe defaults such as `apiKeyHelper` and a default model alias
- `/usr/local/bin/claude`
  - wrapper that defaults to direct AMD Anthropic mode and auto-enables compatibility settings
- `/usr/local/bin/claude-proxy`
  - manual fallback entrypoint that forces the local proxy path
- `/usr/local/bin/claude-route`
  - route inspector that reports whether `claude` will use direct Claude mode or proxy mode
- `~/.claude/amd_gateway_proxy.py`
  - local Anthropic-compatible fallback proxy used only when proxy mode is explicitly selected

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
- offer a manual fallback if the user does not want to share the key

### Step 3: Choose setup path

#### Path A: User provides key

Proceed with automatic local setup:

1. update the user-local shell config to export `AMD_LLM_GATEWAY_KEY`
2. install or update the `claude` wrapper so its default route is direct AMD Anthropic; note that `/usr/local/bin/claude` may require elevated permissions
3. install or update `claude-proxy` as the manual fallback entrypoint
4. install or update `claude-route` so users can verify the real route independently of model labels
5. keep repository examples placeholder-based only
6. source the shell config if needed or ask the user to open a new shell

#### Path B: User does not provide key

Do not write fake values. Instead:

1. give redacted commands using `PASTE_YOUR_KEY_HERE`
2. explain which local files the user must update
3. tell the user which verification commands to run after they set the key

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

Proxy should be manual-only:

```bash
claude-proxy -p --output-format json 'Reply with exactly OK'
```

## Common Failure Modes

1. `AMD_LLM_GATEWAY_KEY` missing
   - ask the user for the key or fall back to placeholder-only guidance
2. wrong `claude` binary is used
   - check `which claude`; wrapper path should be the intended entrypoint
3. route is accidentally proxy even though output shows a Claude-like model label
   - run `claude-route`; do not rely on model name alone
4. direct Anthropic generation hangs
   - use `claude-proxy` as the manual fallback instead of silently changing the default route
5. old shell still has stale env
   - reload the shell or open a new terminal before re-testing

## Validation Checklist

- [ ] no real secret added to repository files
- [ ] user was prompted for key before automatic secret-bearing edits
- [ ] manual fallback uses placeholders only
- [ ] `claude-route` reports direct mode for the default `claude` command
- [ ] direct verification confirms Claude-family model output instead of `gpt-*`
- [ ] `claude -p` text call was tested
- [ ] Bash tool call was tested or any remaining limitation was stated clearly
