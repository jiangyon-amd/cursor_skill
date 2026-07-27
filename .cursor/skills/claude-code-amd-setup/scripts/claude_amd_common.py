#!/usr/bin/env python3
"""Shared helpers for AMD direct Claude Code wrappers.

User-facing model selections stored in ~/.claude/settings.json:
  - claude-sonnet-5     -> API model claude-sonnet-5 + reasoning effort "medium"
  - claude-opus-5       -> API model claude-opus-5 + reasoning effort "medium" (default)
  - claude-opus-5-max   -> API model claude-opus-5 + reasoning effort "max"

The AMD gateway has no separate "-max" deployment, so the "-max" selection is
resolved locally to the real opus 5 model plus `--effort max`.

Claude Code's own per-model default effort is "high". That is more expensive
than this setup wants, so non-max selections pin an explicit "medium" instead of
inheriting the built-in default. Pass `--effort <level>` to override for a
single session.
"""
from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path

DEFAULT_MODEL = "claude-opus-5"
# Real model names the AMD gateway actually serves.
REAL_MODELS = {"claude-sonnet-5", "claude-opus-5"}
# User-facing selections (includes the local "-max" effort alias).
SUPPORTED_MODELS = {"claude-sonnet-5", "claude-opus-5", "claude-opus-5-max"}
MAX_SELECTION = "claude-opus-5-max"
# Explicit effort for non-max selections; overrides Claude Code's "high" default.
DEFAULT_EFFORT = "medium"
MAX_EFFORT = "max"
ANTHROPIC_BASE_URL = "https://llm-api.amd.com/Anthropic"
BACKEND = "claude-amd-anthropic"


def settings_path() -> Path:
    return Path(os.environ.get("HOME", "/root")) / ".claude" / "settings.json"


def normalize_model(raw: str | None) -> str:
    """Map any persisted/alias value to a supported user-facing selection."""
    if raw is None:
        return DEFAULT_MODEL

    value = str(raw).strip()
    if not value:
        return DEFAULT_MODEL

    if value in SUPPORTED_MODELS:
        return value

    lowered = value.lower()

    sonnet_aliases = {
        "sonnet",
        "sonnet[1m]",
        "claude-sonnet-4.5",
        "claude-sonnet-4.5[1m]",
        "claude-sonnet-4.6",
        "claude-sonnet-4.6[1m]",
        "claude-sonnet-4-6",
        "claude-sonnet-5[1m]",
    }
    max_aliases = {
        "max",
        "opus-max",
        "opus[max]",
        "claude-opus-5-max",
        "claude-opus-5[max]",
        "claude-opus-4-8-max",
        "claude-opus-4.8-max",
        "claude-opus-4-8[max]",
    }
    opus_aliases = {
        "opus",
        "opus[1m]",
        "claude-opus-4.5",
        "claude-opus-4.5[1m]",
        "claude-opus-4.6",
        "claude-opus-4.6[1m]",
        "claude-opus-4-7",
        "claude-opus-4.7",
        "claude-opus-4-7[1m]",
        "claude-opus-4.7[1m]",
        "claude-opus-4-8",
        "claude-opus-4.8",
        "claude-opus-4-8[1m]",
        "claude-opus-4.8[1m]",
        "claude-opus-5[1m]",
    }

    if lowered in max_aliases or value in max_aliases:
        return MAX_SELECTION
    if lowered in sonnet_aliases or value in sonnet_aliases:
        return "claude-sonnet-5"
    if lowered in opus_aliases or value in opus_aliases:
        return "claude-opus-5"

    if "max" in lowered and "opus" in lowered:
        return MAX_SELECTION
    if re.match(r"^claude-opus-", value):
        return "claude-opus-5"
    if re.match(r"^claude-sonnet-", value):
        return "claude-sonnet-5"

    return DEFAULT_MODEL


def resolve(selection: str) -> tuple[str, str]:
    """Return (real_api_model, effort) for a user-facing selection."""
    if selection == MAX_SELECTION:
        return "claude-opus-5", MAX_EFFORT
    if selection in REAL_MODELS:
        return selection, DEFAULT_EFFORT
    return DEFAULT_MODEL, DEFAULT_EFFORT


def load_settings() -> tuple[dict, str | None, str | None]:
    path = settings_path()
    if not path.exists():
        return {}, None, None

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return {}, None, str(exc)

    if not isinstance(data, dict):
        return {}, None, "settings.json root must be an object"

    configured = data.get("model")
    configured_model = configured if isinstance(configured, str) else None
    return data, configured_model, None


def ensure_settings() -> tuple[str, str, str, str | None]:
    """Normalize settings.json and return (selection, real_model, effort, configured)."""
    path = settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)

    data, configured_model, parse_error = load_settings()
    if parse_error:
        backup = path.with_name(
            f"settings.json.invalid.{time.strftime('%Y%m%d-%H%M%S')}"
        )
        if path.exists():
            path.rename(backup)
        data = {}

    selection = normalize_model(configured_model)
    real_model, effort = resolve(selection)
    changed = configured_model != selection or parse_error is not None

    if "apiKeyHelper" not in data:
        data["apiKeyHelper"] = "echo amd-gateway-placeholder"
        changed = True

    # Persist the user-facing selection (may be the "-max" alias). The wrapper
    # always launches Claude Code with an explicit `--model <real_model>`, so
    # the alias is never sent verbatim to the gateway.
    if data.get("model") != selection:
        data["model"] = selection
        changed = True

    if changed or not path.exists():
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    return selection, real_model, effort, configured_model


def route_state() -> dict:
    _, configured_model, parse_error = load_settings()
    selection = normalize_model(configured_model)
    real_model, effort = resolve(selection)

    state = {
        "mode": "direct",
        "backend": BACKEND,
        "base_url": ANTHROPIC_BASE_URL,
        "configured_model": configured_model,
        "normalized_model": real_model,
        "selection": selection,
        "effort": effort,
        "default_model": DEFAULT_MODEL,
        "default_effort": DEFAULT_EFFORT,
        "supported_models": sorted(SUPPORTED_MODELS),
    }
    if parse_error:
        state["settings_parse_error"] = parse_error
    return state


def main() -> int:
    import sys

    if len(sys.argv) != 2:
        print(
            "usage: claude_amd_common.py --route|--ensure-settings|--resolve",
            file=sys.stderr,
        )
        return 2

    mode = sys.argv[1]
    if mode == "--route":
        print(json.dumps(route_state(), indent=2))
        return 0

    if mode == "--ensure-settings":
        # Print "<real_model>\t<effort>" so the wrapper can inject CLI flags.
        _, real_model, effort, _ = ensure_settings()
        print(f"{real_model}\t{effort or ''}")
        return 0

    if mode == "--resolve":
        _, configured_model, _ = load_settings()
        real_model, effort = resolve(normalize_model(configured_model))
        print(f"{real_model}\t{effort or ''}")
        return 0

    print(f"unknown mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
