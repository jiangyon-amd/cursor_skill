#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT=""
OUTDIR=""
BASENAME=""
WHISPER_MODEL="small"
DEVICE="cpu"
COMPUTE_TYPE="int8"
TS="5.0"
SKIP_ASR="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) INPUT="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    --basename) BASENAME="$2"; shift 2 ;;
    --whisper-model) WHISPER_MODEL="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --compute-type) COMPUTE_TYPE="$2"; shift 2 ;;
    --verify-timestamp) TS="$2"; shift 2 ;;
    --skip-asr) SKIP_ASR="true"; shift 1 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$INPUT" || -z "$OUTDIR" || -z "$BASENAME" ]]; then
  echo "Usage: run_pipeline.sh --input <mp4> --outdir <dir> --basename <name> [--whisper-model small] [--device cpu] [--skip-asr]" >&2
  exit 1
fi

ZH_WAV="${OUTDIR}/${BASENAME}_zh.wav"
ZH_TIMELINE="${OUTDIR}/${BASENAME}_zh_timeline.txt"
EN_TIMELINE="${OUTDIR}/${BASENAME}_en_timeline.txt"
EN_SRT="${OUTDIR}/${BASENAME}.en.srt"
HARDSUB_VIDEO="${OUTDIR}/${BASENAME}_with_en_hardsub.mp4"
VERIFY_JSON="${OUTDIR}/${BASENAME}_hardsub_verify.json"

if [[ "$SKIP_ASR" != "true" ]]; then
  echo "[1/7] Extract audio"
  python3 "${SCRIPT_DIR}/extract_audio.py" --input "$INPUT" --output "$ZH_WAV"

  echo "[2/7] Transcribe Chinese timeline"
  python3 "${SCRIPT_DIR}/transcribe_zh.py" \
    --input "$ZH_WAV" \
    --output "$ZH_TIMELINE" \
    --model "$WHISPER_MODEL" \
    --device "$DEVICE" \
    --compute-type "$COMPUTE_TYPE"
else
  echo "[1/7] Skip ASR by user flag"
  if [[ ! -f "$ZH_TIMELINE" ]]; then
    echo "Missing required file for --skip-asr: $ZH_TIMELINE" >&2
    exit 2
  fi
fi

if [[ ! -f "$EN_TIMELINE" ]]; then
  echo "[3/7] LLM translation required"
  echo "Please create: $EN_TIMELINE"
  echo "Source file:    $ZH_TIMELINE"
  echo "Rules: preserve timestamp and one-line mapping."
  echo "Re-run this same command after translation file is ready."
  exit 10
fi

echo "[4/7] Convert English timeline to SRT"
python3 "${SCRIPT_DIR}/timeline_to_srt.py" --input "$EN_TIMELINE" --output "$EN_SRT"

echo "[5/7] Prepare font"
mkdir -p /tmp/fonts
if [[ ! -f /tmp/fonts/NotoSans-Regular.ttf ]]; then
  curl -L "https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSans/NotoSans-Regular.ttf" \
    -o /tmp/fonts/NotoSans-Regular.ttf
fi

echo "[6/7] Burn hard subtitles"
python3 - <<PY
import subprocess, imageio_ffmpeg
ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
video = r"""${INPUT}"""
srt = r"""${EN_SRT}"""
out = r"""${HARDSUB_VIDEO}"""
fontsdir = "/tmp/fonts"
vf = f"subtitles={srt}:fontsdir={fontsdir}:force_style='FontName=Noto Sans,FontSize=20,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BorderStyle=1,Outline=2,Shadow=0,Alignment=2,MarginV=24'"
subprocess.run([ffmpeg, "-y", "-i", video, "-vf", vf, "-c:v", "libx264", "-preset", "ultrafast", "-crf", "23", "-c:a", "copy", out], check=True)
print("output=", out)
PY

echo "[7/7] Verify hard subtitle visibility"
python3 "${SCRIPT_DIR}/verify_hardsub.py" \
  --source "$INPUT" \
  --hardsub "$HARDSUB_VIDEO" \
  --timestamp "$TS" \
  --out "$VERIFY_JSON"

echo "Done."
echo "Chinese timeline: $ZH_TIMELINE"
echo "English timeline: $EN_TIMELINE"
echo "SRT:              $EN_SRT"
echo "Hard-sub video:   $HARDSUB_VIDEO"
echo "Verify report:    $VERIFY_JSON"
