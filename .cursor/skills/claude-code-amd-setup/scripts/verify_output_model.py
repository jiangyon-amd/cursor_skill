#!/usr/bin/env python3
from __future__ import annotations

import json
import sys


def main() -> int:
    raw = sys.stdin.read().strip()
    if not raw:
        print("ERROR: no JSON input received", file=sys.stderr)
        return 2

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid JSON input: {exc}", file=sys.stderr)
        return 2

    model_usage = data.get("modelUsage")
    if not isinstance(model_usage, dict) or not model_usage:
        print("ERROR: modelUsage is missing or empty", file=sys.stderr)
        return 2

    bad_models = [name for name in model_usage if not name.startswith("claude-")]
    if bad_models:
        print(
            "ERROR: non-Claude model(s) reported: " + ", ".join(sorted(bad_models)),
            file=sys.stderr,
        )
        return 1

    print("OK: Claude model(s) reported: " + ", ".join(sorted(model_usage)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
