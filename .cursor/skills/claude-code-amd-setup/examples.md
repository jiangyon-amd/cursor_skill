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
   - `/usr/local/bin/claude-route`
4. Verify the route first:

```bash
claude-route
```

5. Verify direct-mode output:

```bash
claude -p --output-format json 'Reply with exactly OK' | \
  python3 ".cursor/skills/claude-code-amd-setup/scripts/verify_output_model.py"
```

6. Confirm that the reported model is either `claude-sonnet-5` or `claude-opus-5`.
7. Confirm that no real key was written into repository files.

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

4. Explain that the desired default is direct `claude` using `claude-opus-5` at `--effort medium` (use `claude-opus-5-max` for max reasoning effort).
5. Explain that model switching should be done by editing `~/.claude/settings.json`, for example to `claude-sonnet-5`.
6. Explain which files the user must update locally.
7. Give verification commands the user can run after they finish:

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
3. Run `claude-route` to confirm the machine is on direct mode and inspect the configured versus normalized model.
4. Preserve the no-secret-in-git rule.
5. If `~/.claude/settings.json` contains `opus[1m]`, a retired model such as `claude-opus-4-8`, or another unsupported alias, repair it to `claude-sonnet-5` or `claude-opus-5`.
6. Re-test text output, model route, and a simple Bash tool call before declaring success.

## Example 4: `/model` Does Not Offer Opus 5

User request:

```text
`claude-route` says Opus 5, but `/model` does not list it and the menu tops out at an older Opus. Fix the menu without breaking the AMD direct wrapper.
```

Expected behavior:

1. Confirm that `which claude` still points to the wrapper, usually `/usr/local/bin/claude`.
2. Do not move `~/.local/bin` ahead of the wrapper in `PATH`.
3. Check `claude --version` and inspect `readlink -f ~/.local/bin/claude` when present.
4. If the native Claude Code build is old, run `claude-selfupdate`. Explain that `claude update` is a dead end here, because the wrapper's `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` makes Claude Code skip its latest-version lookup.
5. Explain that already-open interactive sessions can keep stale menu text until they are restarted.
6. Explain that the menu comes from the binary's bundled model registry, so a just-released gateway model can be missing from it. This does not break routing: the wrapper passes `--model claude-opus-5` explicitly, and `modelUsage` in the JSON output proves which model answered.
7. Do not "fix" a missing menu entry by downgrading `~/.claude/settings.json` to an older model.
8. Re-run `claude-route` and a simple `claude -p --output-format json ...` check before declaring the fix complete.

## Example 5: The Native Build Never Updates

User request:

```text
My Claude Code has been stuck on the same version for weeks and `claude update` says nothing. Is the AMD wrapper blocking it?
```

Expected behavior:

1. Confirm the version with `claude --version` and compare it against the release CDN using `claude-selfupdate --check`.
2. Explain the cause rather than guessing: the wrapper exports `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, and in that essential-traffic mode Claude Code skips its latest-version lookup, so the built-in updater has nothing to report.
3. Do not "fix" it by unsetting that variable in the wrapper or by running the official installer, which can reorder `PATH` ahead of `/usr/local/bin/claude`.
4. Run `claude-selfupdate` to install the newer build; it verifies the SHA256 against the release manifest before swapping the symlink.
5. Re-verify with `claude-route`, `which claude`, and a real `claude -p --output-format json ...` call.
6. Tell the user to restart open interactive sessions, since a running process keeps the build it started with.
7. Mention `claude-selfupdate --prune 2` if `~/.local/share/claude/versions/` has grown, and `--rollback` if the new build misbehaves.

## Example 6: Cost Control Via Effort

User request:

```text
Opus 5 sessions feel expensive. Can I lower how hard it thinks without switching models?
```

Expected behavior:

1. Explain that this setup already pins non-max selections to `--effort medium`, instead of Claude Code's built-in `high` default.
2. Confirm the active level with `claude-route` and check the `effort` field.
3. For a single cheaper session, suggest `claude --effort low`; the wrapper stands down when the caller passes `--effort`.
4. Explain that `claude-opus-5-max` is the opposite direction: same model, `--effort max`.
5. Point out that `claude-sonnet-5` remains the lower-cost model choice if effort tuning is not enough.
