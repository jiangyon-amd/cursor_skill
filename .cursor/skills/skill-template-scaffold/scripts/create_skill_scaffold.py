#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path

NAME_RE = re.compile(r"^[a-z0-9-]{1,64}$")


def validate_name(name: str) -> None:
    if not NAME_RE.fullmatch(name):
        raise ValueError(
            "Invalid --skill-name. Use lowercase letters/numbers/hyphens only, max 64 chars."
        )


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a new Cursor skill scaffold.")
    parser.add_argument("--target-root", required=True, help="Target skills root directory")
    parser.add_argument("--skill-name", required=True, help="Skill folder/frontmatter name")
    parser.add_argument("--title", required=True, help="Human-readable skill title")
    parser.add_argument("--description", required=True, help="Frontmatter description")
    args = parser.parse_args()

    validate_name(args.skill_name)
    if not args.description.strip():
        raise ValueError("--description must be non-empty")

    target_root = Path(args.target_root)
    skill_dir = target_root / args.skill_name

    if skill_dir.exists():
        raise FileExistsError(f"Target already exists: {skill_dir}")

    skill_md = f"""---
name: {args.skill_name}
description: {args.description.strip()}
---

# {args.title}

## Purpose

Describe what this skill automates and why it exists.

## When to Use

- Trigger condition 1
- Trigger condition 2

## Instructions

1. Step one
2. Step two
3. Step three

## Validation

- [ ] output is complete
- [ ] output format is correct
- [ ] edge cases are handled
"""

    examples_md = f"""# Examples

## Example 1

Explain a realistic usage scenario for `{args.skill_name}`.

## Example 2

Show another scenario with different constraints.
"""

    scripts_readme = """# Scripts README

Document helper scripts for this skill.

## Conventions

- Keep scripts deterministic.
- Prefer explicit error messages.
- Add usage examples for each script.
"""

    healthcheck = """#!/usr/bin/env bash
set -euo pipefail

echo "healthcheck: ok"
"""

    write_file(skill_dir / "SKILL.md", skill_md)
    write_file(skill_dir / "examples.md", examples_md)
    write_file(skill_dir / "scripts" / "README.md", scripts_readme)
    write_file(skill_dir / "scripts" / "healthcheck.sh", healthcheck)

    print(f"created={skill_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
