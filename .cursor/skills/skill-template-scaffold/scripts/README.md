# Scripts README

This folder contains scaffold and validation utilities for skill authoring.

## `create_skill_scaffold.py`

Creates a new skill directory with baseline files.

### Usage

```bash
python3 ".cursor/skills/skill-template-scaffold/scripts/create_skill_scaffold.py" \
  --target-root ".cursor/skills" \
  --skill-name "my-new-skill" \
  --title "My New Skill" \
  --description "Does A and B. Use when users ask for C."
```

### Behavior

- validates skill name format
- creates:
  - `SKILL.md`
  - `examples.md`
  - `scripts/README.md`
  - `scripts/healthcheck.sh`
- fails if target skill directory already exists

## `validate_skill.py`

Validates a generated skill folder.

### Usage

```bash
python3 ".cursor/skills/skill-template-scaffold/scripts/validate_skill.py" \
  --skill-dir ".cursor/skills/my-new-skill"
```

### Checks

- required files exist
- `SKILL.md` frontmatter exists
- `name` format is valid
- `description` exists and is non-empty
- scripts doc exists when `scripts/` exists

### Exit codes

- `0`: all checks pass
- `2`: validation failed
- `1`: usage/runtime error
