# Examples

## Example 1: Automatic Setup After User Provides Key

User request:

```text
Set up Claude Code for AMD LLM Gateway on this machine, but do not put my key into git.
```

Expected behavior:

1. Check whether `claude` is installed and whether `AMD_LLM_GATEWAY_KEY` is already set.
2. If the key is missing, ask the user to provide it before editing local secret-bearing files.
3. Once the user provides the key, update local files only:
   - `~/.bashrc`
   - `~/.claude/settings.json`
   - `/usr/local/bin/claude`
   - `/usr/local/bin/claude-proxy`
   - `/usr/local/bin/claude-route`
   - `~/.claude/amd_gateway_proxy.py`
4. Verify the route first:

```bash
claude-route
```

5. Verify direct-mode output:

```bash
claude -p --output-format json 'Reply with exactly OK' | \
  python3 ".cursor/skills/claude-code-amd-setup/scripts/verify_output_model.py"
```

6. Confirm that no real key was written into repository files.

## Example 2: Manual Fallback When User Will Not Share Key

User request:

```text
I want the setup skill, but I do not want to paste the gateway key into chat.
```

Expected behavior:

1. Do not invent or hard-code any key.
2. Switch to placeholder-based instructions.
3. Provide a safe snippet such as:

```bash
export AMD_LLM_GATEWAY_KEY="PASTE_YOUR_KEY_HERE"
```

4. Explain that the desired default is direct `claude`, with `claude-proxy` kept only as a manual fallback.
5. Explain which files the user must update locally.
6. Give verification commands the user can run after they finish:

```bash
claude-route
claude -p --output-format json 'Reply with exactly OK' | \
  python3 ".cursor/skills/claude-code-amd-setup/scripts/verify_output_model.py"
```

## Example 3: Repair an Existing Broken Setup

User request:

```text
Claude Code starts, but AMD Anthropic generation hangs. Fix it without exposing my key.
```

Expected behavior:

1. Check the current wrapper path with `which claude`.
2. Check whether the key is present without printing it.
3. Run `claude-route` to confirm whether the machine is actually on direct mode or proxy mode.
4. Preserve the no-secret-in-git rule.
5. If direct Anthropic generation is unreliable, keep `claude` on direct mode only if it passes verification; otherwise provide `claude-proxy` as the manual fallback.
6. Re-test text output, model route, and a simple Bash tool call before declaring success.
