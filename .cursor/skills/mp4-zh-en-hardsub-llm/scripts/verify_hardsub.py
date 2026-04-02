#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

import imageio_ffmpeg
import numpy as np
from PIL import Image


def extract_frame(ffmpeg: str, video: str, timestamp: float, output: Path) -> None:
    subprocess.run(
        [ffmpeg, "-y", "-ss", str(timestamp), "-i", video, "-frames:v", "1", str(output)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify hardsub visibility by frame diff.")
    parser.add_argument("--source", required=True, help="Source video path")
    parser.add_argument("--hardsub", required=True, help="Hard-sub video path")
    parser.add_argument("--timestamp", type=float, default=5.0, help="Frame timestamp to compare")
    parser.add_argument("--out", required=True, help="Output JSON report path")
    args = parser.parse_args()

    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    with tempfile.TemporaryDirectory() as td:
        f1 = Path(td) / "src.png"
        f2 = Path(td) / "hard.png"
        extract_frame(ffmpeg, args.source, args.timestamp, f1)
        extract_frame(ffmpeg, args.hardsub, args.timestamp, f2)

        src = np.array(Image.open(f1).convert("RGB"))
        hard = np.array(Image.open(f2).convert("RGB"))
        diff = np.abs(src.astype(np.int16) - hard.astype(np.int16)).astype(np.uint8)

        h = diff.shape[0]
        bottom = diff[int(h * 0.72) :, :, :]
        bottom_mean_diff = float(bottom.mean())
        nonzero_bottom_pixels = int((bottom > 20).any(axis=2).sum())

        report = {
            "timestamp": args.timestamp,
            "bottom_mean_diff": bottom_mean_diff,
            "nonzero_bottom_pixels": nonzero_bottom_pixels,
            "pass": (nonzero_bottom_pixels > 1000 and bottom_mean_diff > 1.0),
        }

    Path(args.out).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report["pass"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
