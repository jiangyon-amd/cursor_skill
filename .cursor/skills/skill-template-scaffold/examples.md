# Examples

## Example 1: Create a Python Debugging Skill

```bash
python3 ".cursor/skills/skill-template-scaffold/scripts/create_skill_scaffold.py" \
  --target-root ".cursor/skills" \
  --skill-name "python-debug-workflow" \
  --title "Python Debug Workflow" \
  --description "Troubleshoots Python runtime failures with reproducible steps. Use when users report exceptions, flaky tests, or broken CLI behavior."
```

Then validate:

```bash
python3 ".cursor/skills/skill-template-scaffold/scripts/validate_skill.py" \
  --skill-dir ".cursor/skills/python-debug-workflow"
```

## Example 2: Create a Release-Notes Skill

```bash
python3 ".cursor/skills/skill-template-scaffold/scripts/create_skill_scaffold.py" \
  --target-root ".cursor/skills" \
  --skill-name "release-notes-generator" \
  --title "Release Notes Generator" \
  --description "Produces changelog-ready release notes from commit history and PR summaries. Use when users ask to draft release notes."
```

Then validate:

```bash
python3 ".cursor/skills/skill-template-scaffold/scripts/validate_skill.py" \
  --skill-dir ".cursor/skills/release-notes-generator"
```
