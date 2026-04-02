#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path

NAME_RE = re.compile(r"^[a-z0-9-]{1,64}$")
FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)


def parse_frontmatter(text: str) -> dict[str, str]:
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}
    out: dict[str, str] = {}
    for line in m.group(1).splitlines():
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        out[k.strip()] = v.strip()
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Cursor skill directory shape/content.")
    parser.add_argument("--skill-dir", required=True, help="Path to a skill directory")
    args = parser.parse_args()

    skill_dir = Path(args.skill_dir)
    errors: list[str] = []

    if not skill_dir.exists() or not skill_dir.is_dir():
        errors.append(f"skill dir not found: {skill_dir}")
    required = [
        skill_dir / "SKILL.md",
        skill_dir / "examples.md",
        skill_dir / "scripts" / "README.md",
    ]
    for p in required:
        if not p.exists():
            errors.append(f"missing required file: {p}")

    skill_md = skill_dir / "SKILL.md"
    if skill_md.exists():
        text = skill_md.read_text(encoding="utf-8", errors="ignore")
        fm = parse_frontmatter(text)
        if not fm:
            errors.append("SKILL.md frontmatter missing or malformed")
        else:
            name = fm.get("name", "")
            desc = fm.get("description", "")
            if not NAME_RE.fullmatch(name):
                errors.append("frontmatter name invalid (use lowercase letters/numbers/hyphens, max 64)")
            if not desc.strip():
                errors.append("frontmatter description empty")

    if errors:
        for e in errors:
            print(f"ERROR: {e}")
        return 2

    print("OK: skill validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
