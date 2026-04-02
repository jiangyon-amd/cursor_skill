#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path

# Supports:
# [00001.90 --> 00036.32] text
# [00001.90s - 00036.32s] text
PATTERN = re.compile(r"^\[(\d+(?:\.\d+)?)(?:s)?\s*(?:-->|-)\s*(\d+(?:\.\d+)?)(?:s)?\]\s*(.*)$")


def to_srt_time(sec_str: str) -> str:
    sec = float(sec_str)
    hours = int(sec // 3600)
    minutes = int((sec % 3600) // 60)
    seconds = int(sec % 60)
    millis = int(round((sec - int(sec)) * 1000))
    if millis == 1000:
        millis = 0
        seconds += 1
    if seconds == 60:
        seconds = 0
        minutes += 1
    if minutes == 60:
        minutes = 0
        hours += 1
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{millis:03d}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert timeline text to SRT.")
    parser.add_argument("--input", required=True, help="Input timeline txt path")
    parser.add_argument("--output", required=True, help="Output SRT path")
    args = parser.parse_args()

    lines = Path(args.input).read_text(encoding="utf-8", errors="ignore").splitlines()

    blocks = []
    idx = 0
    for raw in lines:
        m = PATTERN.match(raw.strip())
        if not m:
            continue
        start, end, text = m.groups()
        idx += 1
        blocks.append(str(idx))
        blocks.append(f"{to_srt_time(start)} --> {to_srt_time(end)}")
        blocks.append(text.strip() if text.strip() else "...")
        blocks.append("")

    Path(args.output).write_text("\n".join(blocks), encoding="utf-8")
    print(f"segments={idx}")
    print(f"output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
