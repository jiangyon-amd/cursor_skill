# Scripts README

This directory contains executable scripts for the `mp4-zh-en-hardsub-llm` skill.

## Files

- `extract_audio.py`  
  MP4 -> mono 16k WAV.

- `transcribe_zh.py`  
  WAV -> Chinese timeline text (`[start --> end] text`).

- `timeline_to_srt.py`  
  Timeline text -> SRT. Supports both:
  - `[00001.90 --> 00036.32] text`
  - `[00001.90s - 00036.32s] text`

- `verify_hardsub.py`  
  Verifies hard subtitle visibility by frame-diff against source video.

- `run_pipeline.sh`  
  Semi-automated pipeline with mandatory LLM translation checkpoint.

## Install Dependencies

```bash
python3 -m pip install --user imageio-ffmpeg faster-whisper numpy pillow
```

## Main Pipeline

```bash
bash ".cursor/skills/mp4-zh-en-hardsub-llm/scripts/run_pipeline.sh" \
  --input "/workspace/input.mp4" \
  --outdir "/workspace" \
  --basename "input" \
  --whisper-model "small"
```

### LLM translation checkpoint

The pipeline intentionally exits with code `10` if `<basename>_en_timeline.txt` is missing.

You must create this file via LLM translation (not Python translation library), then re-run the same command.

## Offline/Restricted Resume Mode

If Chinese timeline already exists and ASR model download is blocked:

```bash
bash ".cursor/skills/mp4-zh-en-hardsub-llm/scripts/run_pipeline.sh" \
  --input "/workspace/input.mp4" \
  --outdir "/workspace" \
  --basename "input" \
  --skip-asr
```

Requires:
- `/workspace/input_zh_timeline.txt`
- `/workspace/input_en_timeline.txt` (LLM-generated)

## Individual Script Usage

### 1) Extract audio

```bash
python3 ".cursor/skills/mp4-zh-en-hardsub-llm/scripts/extract_audio.py" \
  --input "/workspace/input.mp4" \
  --output "/workspace/input_zh.wav"
```

### 2) Chinese transcription

```bash
python3 ".cursor/skills/mp4-zh-en-hardsub-llm/scripts/transcribe_zh.py" \
  --input "/workspace/input_zh.wav" \
  --output "/workspace/input_zh_timeline.txt" \
  --model "small" \
  --device "cpu" \
  --compute-type "int8"
```

### 3) Timeline to SRT

```bash
python3 ".cursor/skills/mp4-zh-en-hardsub-llm/scripts/timeline_to_srt.py" \
  --input "/workspace/input_en_timeline.txt" \
  --output "/workspace/input.en.srt"
```

### 4) Hard-sub verification

```bash
python3 ".cursor/skills/mp4-zh-en-hardsub-llm/scripts/verify_hardsub.py" \
  --source "/workspace/input.mp4" \
  --hardsub "/workspace/input_with_en_hardsub.mp4" \
  --timestamp 5.0 \
  --out "/workspace/input_hardsub_verify.json"
```

## Verification Criteria

`verify_hardsub.py` returns JSON:

```json
{
  "timestamp": 5.0,
  "bottom_mean_diff": 2.95,
  "nonzero_bottom_pixels": 14390,
  "pass": true
}
```

Recommended pass thresholds:
- `nonzero_bottom_pixels > 1000`
- `bottom_mean_diff > 1.0`

## Exit Codes

- `run_pipeline.sh`
  - `0`: success
  - `1`: argument/general failure
  - `2`: `--skip-asr` enabled but Chinese timeline missing
  - `10`: waiting for LLM English timeline file

- `verify_hardsub.py`
  - `0`: pass
  - `2`: fail
