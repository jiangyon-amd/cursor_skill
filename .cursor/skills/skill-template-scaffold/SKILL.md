---
name: skill-template-scaffold
description: Create a complete reusable Cursor Skill scaffold with strict structure, scripts, examples, and validation workflow. Use when the user asks to create a new skill template, scaffold a new skill, or standardize future skill authoring.
---

# Skill Template Scaffold

## Purpose

Provide a rigorous, repeatable template for creating new Cursor skills with:
- standard file structure
- strict metadata and naming checks
- usage examples
- script documentation
- validation hooks

## When to Use

Use this skill when:
- user wants a "skill template" or "scaffold"
- team needs consistent skill quality across repositories
- future skills should be generated quickly with minimal drift

## Generated Skill Structure

```text
<skill-name>/
├── SKILL.md
├── examples.md
└── scripts/
    ├── README.md
    └── healthcheck.sh
```

## Non-Negotiable Standards

1. `name` in frontmatter:
   - lowercase letters, numbers, hyphens only
   - max 64 chars
2. `description` includes:
   - what the skill does
   - when it should be used
3. Paths and commands are Linux-style.
4. `SKILL.md` keeps operational steps explicit and testable.
5. Every scaffolded skill must pass validator checks before commit.

## Scripts in This Template Skill

- `scripts/create_skill_scaffold.py`
  - creates a new skill skeleton under target root
  - writes starter `SKILL.md`, `examples.md`, and `scripts` docs
- `scripts/validate_skill.py`
  - validates frontmatter, naming, required files, and script docs

## Quick Start

Create a new skill scaffold:

```bash
python3 ".cursor/skills/skill-template-scaffold/scripts/create_skill_scaffold.py" \
  --target-root ".cursor/skills" \
  --skill-name "my-new-skill" \
  --title "My New Skill" \
  --description "Automates X and Y. Use when users ask for Z."
```

Validate the new skill:

```bash
python3 ".cursor/skills/skill-template-scaffold/scripts/validate_skill.py" \
  --skill-dir ".cursor/skills/my-new-skill"
```

## Delivery Checklist

- [ ] scaffold generated successfully
- [ ] validator passes with exit code 0
- [ ] example usage updated if needed
- [ ] committed with clear message
