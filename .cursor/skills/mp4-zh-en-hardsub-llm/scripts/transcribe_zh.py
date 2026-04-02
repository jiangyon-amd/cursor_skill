#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from faster_whisper import WhisperModel


def main() -> int:
    parser = argparse.ArgumentParser(description="Transcribe audio to Chinese timeline text.")
    parser.add_argument("--input", required=True, help="Input wav path")
    parser.add_argument("--output", required=True, help="Output zh timeline txt")
    parser.add_argument("--model", default="small", help="Whisper model size")
    parser.add_argument("--device", default="cpu", help="cpu or cuda")
    parser.add_argument("--compute-type", default="int8", help="int8/float16")
    args = parser.parse_args()

    model = WhisperModel(args.model, device=args.device, compute_type=args.compute_type)
    segments, _ = model.transcribe(args.input, language="zh", vad_filter=True)

    out = []
    for seg in segments:
        text = seg.text.strip()
        if not text:
            continue
        out.append(f"[{seg.start:08.2f} --> {seg.end:08.2f}] {text}")

    Path(args.output).write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"segments={len(out)}")
    print(f"output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
