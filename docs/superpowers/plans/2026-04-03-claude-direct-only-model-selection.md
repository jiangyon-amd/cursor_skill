# Claude Direct-Only Model Selection Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make local Claude Code use only the AMD Anthropic direct endpoint with `claude-sonnet-4.6` as the default model, `claude-opus-4.6` as the supported high-tier model, and automatic repair of incompatible persisted model aliases.

**Architecture:** Keep a single local `claude` wrapper as the entrypoint. Use `~/.claude/settings.json` as the model source of truth, but normalize unsupported or legacy values to supported exact direct models before launching Claude Code. Update the skill repository so diagnostics and documentation match the new direct-only behavior.

**Tech Stack:** Bash, Python 3, Claude Code local config, Markdown docs

---

## Chunk 1: Local Direct Wrapper

### Task 1: Update local wrapper defaults and remove proxy path

**Files:**
- Modify: `/usr/local/bin/claude`
- Delete: `/usr/local/bin/claude-proxy`
- Modify: `/usr/local/bin/claude-route`

- [ ] **Step 1: Write the failing checks**

Run:

```bash
python3 - <<'PY'
import json
from pathlib import Path
p = Path('/root/.claude/settings.json')
data = json.loads(p.read_text())
data['model'] = 'opus[1m]'
p.write_text(json.dumps(data, indent=2) + '\n')
PY
claude -p --output-format json 'Reply with exactly OK'
```

Expected before the fix: API error `400 ... BadRequest`.

- [ ] **Step 2: Update wrapper implementation**

Implement:
- direct-only base URL handling
- `claude-sonnet-4.6` and `claude-opus-4.6` defaults
- settings normalization for `sonnet`, `opus`, 4.5 aliases, and `1m` aliases
- removal of proxy startup logic

- [ ] **Step 3: Run direct verification**

Run:

```bash
claude-route
claude -p --output-format json 'Reply with exactly OK'
```

Expected: direct route, successful JSON result, no proxy path.

## Chunk 2: Direct Model Verification

### Task 2: Improve verification helpers

**Files:**
- Modify: `/data/jiangyon/cursor_skill/.cursor/skills/claude-code-amd-setup/scripts/healthcheck.sh`
- Modify: `/data/jiangyon/cursor_skill/.cursor/skills/claude-code-amd-setup/scripts/verify_output_model.py`

- [ ] **Step 1: Write the failing checks**

Run:

```bash
claude -p --model 'claude-opus-4.5[1m]' --output-format json 'Reply with exactly OK' | \
  python3 "/data/jiangyon/cursor_skill/.cursor/skills/claude-code-amd-setup/scripts/verify_output_model.py"
```

Expected before the fix: unhelpful `modelUsage is missing or empty`.

- [ ] **Step 2: Update helper behavior**

Implement:
- explicit API-error reporting in `verify_output_model.py`
- current configured model reporting in `healthcheck.sh`
- supported direct-only model validation in `healthcheck.sh`

- [ ] **Step 3: Run helper verification**

Run:

```bash
bash "/data/jiangyon/cursor_skill/.cursor/skills/claude-code-amd-setup/scripts/healthcheck.sh"
claude -p --output-format json 'Reply with exactly OK' | \
  python3 "/data/jiangyon/cursor_skill/.cursor/skills/claude-code-amd-setup/scripts/verify_output_model.py"
```

Expected: healthcheck shows direct route plus configured model, verifier reports a Claude 4.6 model on successful calls.

## Chunk 3: Skill Documentation

### Task 3: Rewrite the skill to direct-only

**Files:**
- Modify: `/data/jiangyon/cursor_skill/.cursor/skills/claude-code-amd-setup/SKILL.md`
- Modify: `/data/jiangyon/cursor_skill/.cursor/skills/claude-code-amd-setup/examples.md`
- Modify: `/data/jiangyon/cursor_skill/.cursor/skills/claude-code-amd-setup/scripts/README.md`

- [ ] **Step 1: Update docs**

Implement:
- remove proxy fallback guidance
- document supported direct models
- explain why `/model` can persist incompatible aliases
- instruct users to switch models via `~/.claude/settings.json`
- document direct-only verification steps

- [ ] **Step 2: Validate the skill**

Run:

```bash
python3 "/data/jiangyon/cursor_skill/.cursor/skills/skill-template-scaffold/scripts/validate_skill.py" \
  --skill-dir "/data/jiangyon/cursor_skill/.cursor/skills/claude-code-amd-setup"
```

Expected: `OK: skill validation passed`.

## Chunk 4: Final Verification and Commit

### Task 4: Verify supported direct models and commit skill repo changes

**Files:**
- Modify: `/data/jiangyon/cursor_skill/...` updated skill files

- [ ] **Step 1: Verify default direct model**

Run:

```bash
python3 - <<'PY'
import json
from pathlib import Path
p = Path('/root/.claude/settings.json')
data = json.loads(p.read_text())
data['model'] = 'claude-sonnet-4.6'
p.write_text(json.dumps(data, indent=2) + '\n')
PY
claude -p --output-format json 'Reply with exactly OK'
```

Expected: success with `claude-sonnet-4.6`.

- [ ] **Step 2: Verify high-tier direct model**

Run:

```bash
python3 - <<'PY'
import json
from pathlib import Path
p = Path('/root/.claude/settings.json')
data = json.loads(p.read_text())
data['model'] = 'claude-opus-4.6'
p.write_text(json.dumps(data, indent=2) + '\n')
PY
claude -p --output-format json 'Reply with exactly OK'
```

Expected: success with `claude-opus-4.6`.

- [ ] **Step 3: Verify Bash tool use**

Run:

```bash
claude -p --output-format json --allowedTools Bash -- \
  'Use the Bash tool to run pwd, then answer with only the absolute path.'
```

Expected: success with the absolute path result.

- [ ] **Step 4: Commit skill repo changes**

```bash
git add docs/superpowers/specs/2026-04-03-claude-direct-only-model-selection-design.md \
  docs/superpowers/plans/2026-04-03-claude-direct-only-model-selection.md \
  .cursor/skills/claude-code-amd-setup
git commit -m "Document direct-only Claude model selection"
```
