---
name: mp4-zh-en-hardsub-llm
description: End-to-end workflow for MP4 subtitle production: extract audio, transcribe Chinese, translate Chinese to English using the LLM itself (not Python translation libraries), generate SRT, burn English hard subtitles into video, and verify subtitle visibility before finishing. Use when users ask for Chinese-to-English subtitle generation, timestamped translation, or hard-sub output video.
---

# MP4 -> Chinese -> English -> Hard Subtitle (LLM Translation Only)

## Skill Location and Scope

- **Project skill path**: `.cursor/skills/mp4-zh-en-hardsub-llm/SKILL.md`
- **Absolute path example**: `/workspace/.cursor/skills/mp4-zh-en-hardsub-llm/SKILL.md`
- **Scope**: current repository only (team-shared if committed)

## Non-Negotiable Rules

1. English translation must be done by the **LLM itself**.
2. Do **not** use Python translation libraries/services for core translation, including:
   - `deep-translator`
   - `argostranslate`
   - Marian/NLLB/Helsinki translation pipelines
3. Keep timestamp alignment consistent with source segments unless user explicitly asks to merge/split.
4. Do not declare success until subtitle visibility is verified on rendered output.
5. If both hard and soft subtitle outputs are produced, label them clearly.

## Prerequisites

- Python 3.10+
- Packages: imageio-ffmpeg, faster-whisper, numpy, Pillow
- Network access for first-time ASR model download from Hugging Face (or pre-cached local model)
- Write permission to output directory

## Inputs and Outputs

### Required input
- Source video path, for example: `"/workspace/input.mp4"`

### Required outputs
- Chinese timeline text: `<basename>_zh_timeline.txt`
- English timeline text: `<basename>_en_timeline.txt`
- English SRT: `<basename>.en.srt`
- Hard-sub video: `<basename>_with_en_hardsub.mp4`

### Optional outputs
- Soft-sub video with embedded subtitle track
- 10-20 second hardsub sample clip for quick user validation

## Standard Pipeline

### Step 1: Environment and file checks

1. Confirm source file exists and is readable.
2. Confirm writable output directory.
3. If system `ffmpeg` is missing, use Python `imageio-ffmpeg` binary.
4. Confirm the run user has permission to create output files.

Suggested commands:

```bash
ls -l "/workspace/input.mp4"
python3 -c "import imageio_ffmpeg,sys; print(imageio_ffmpeg.get_ffmpeg_exe())"
```

### Step 2: Extract audio

Extract mono 16k WAV for speech recognition:

```bash
python3 - <<'PY'
from pathlib import Path
import subprocess
import imageio_ffmpeg

video = Path("/workspace/input.mp4")
audio = Path("/workspace/input_zh.wav")
ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
subprocess.run([ffmpeg, "-y", "-i", str(video), "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(audio)], check=True)
print(audio)
PY
```

### Step 3: Chinese transcription with timestamps

Use ASR (for example `faster-whisper`) to produce:

```text
[00001.90 --> 00036.32] Chinese text...
```

Hard requirements:
- UTF-8 output
- one segment per line
- timestamp format fixed as `[start --> end]`

### Step 4: LLM-based Chinese to English translation

This step must be performed by the LLM itself (manual/tool-assisted prompt workflow):

1. Read Chinese timeline file in chunks.
2. Translate each segment while preserving timestamp.
3. Keep one output line per input line (no re-indexing, no timestamp drift).
4. Write `input_en_timeline.txt` with format:

```text
[00001.90 --> 00036.32] English text...
```

#### Technical terminology policy

Prefer normalized forms:
- Kernel
- LDS (Local Data Share)
- Shared Memory
- Register
- Bank Conflict
- Tiling
- Occupancy
- Bottleneck
- ROCm / rocprof
- Triton

If ASR text is noisy:
- preserve likely technical intent,
- do not inject offensive words absent in source meaning,
- keep terms consistent across file.

#### Suggested LLM translation prompt template

```text
You are translating timestamped Chinese subtitles to English.
Rules:
1) Keep each line and timestamp exactly.
2) Translate only text after timestamp.
3) Use technical terms consistently: Kernel, LDS, Shared Memory, Register, Bank Conflict, Tiling, Occupancy, Bottleneck, ROCm, rocprof, Triton.
4) Do not omit lines. Do not merge lines. Do not add commentary.
5) Keep concise spoken-English style.
```

### Step 5: Convert English timeline to SRT

Convert `[start --> end] text` to SRT blocks:

```text
1
00:00:01,900 --> 00:00:36,320
English line...
```

Save as `input.en.srt`.

### Step 6: Burn hard subtitles into video

Use subtitle filter with explicit font setup.
If system fonts are unavailable, download a known TTF (for example Noto Sans) and provide `fontsdir`.

Example:

```bash
python3 - <<'PY'
import subprocess, imageio_ffmpeg
ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
video = "/workspace/input.mp4"
srt = "/workspace/input.en.srt"
out = "/workspace/input_with_en_hardsub.mp4"
fontsdir = "/tmp/fonts"
vf = f"subtitles={srt}:fontsdir={fontsdir}:force_style='FontName=Noto Sans,FontSize=20,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BorderStyle=1,Outline=2,Shadow=0,Alignment=2,MarginV=24'"
subprocess.run([ffmpeg, "-y", "-i", video, "-vf", vf, "-c:v", "libx264", "-preset", "ultrafast", "-crf", "23", "-c:a", "copy", out], check=True)
print(out)
PY
```

### Step 7: Mandatory verification before finishing

Perform all checks:

1. **Render check**: Ensure ffmpeg process succeeded with exit code 0.
2. **Visibility check**: Compare source vs hardsub frame at subtitle-active timestamp and check bottom-region pixel delta.
3. **Content check**: Manually inspect at least 3 moments (start/middle/end) for readable subtitle overlay.

Suggested thresholds:
- `nonzero_bottom_pixels > 1000`
- `bottom_mean_diff > 1.0`

If verification fails:
- Fix font setup (`fontsdir`, font name)
- Re-render
- Re-verify

Do not declare success until verification passes.

## Full Use Case (Real Example)

### Scenario
- Input: `/workspace/Use_AI.mp4`
- Goal: Chinese transcription -> LLM English translation -> hard-sub video output

### Expected artifact set
- `/workspace/Use_AI_zh.wav`
- `/workspace/Use_AI_zh_timeline.txt`
- `/workspace/Use_AI_en_timeline.txt` (LLM-generated)
- `/workspace/Use_AI.en.srt`
- `/workspace/Use_AI_with_en_hardsub.mp4`
- Optional: `/workspace/Use_AI_hardsub_20s_sample.mp4`

### Execution outline
1. Extract WAV from MP4.
2. Run ASR to produce Chinese timeline.
3. Translate timeline with LLM in batches until full file is covered.
4. Convert English timeline to SRT.
5. Burn hard subtitles (font-explicit).
6. Run visibility validation.
7. Deliver file paths and playback recommendation.


## Bundled Scripts

- `scripts/extract_audio.py`: MP4 -> mono 16k WAV
- `scripts/transcribe_zh.py`: WAV -> Chinese timeline text
- `scripts/timeline_to_srt.py`: timeline text -> SRT
- `scripts/verify_hardsub.py`: frame-diff based hard-sub visibility verification
- `scripts/run_pipeline.sh`: semi-automated end-to-end pipeline with mandatory LLM translation checkpoint (supports --skip-asr for offline resume)

### Reproducible One-Command Entry (with LLM checkpoint)

```bash
bash "/workspace/.cursor/skills/mp4-zh-en-hardsub-llm/scripts/run_pipeline.sh"   --input "/workspace/Use_AI.mp4"   --outdir "/workspace"   --basename "Use_AI"   --whisper-model "small"
```

The command exits with code `10` when LLM translation file is missing. After creating `<basename>_en_timeline.txt`, run the same command again to finish.

## Strict Delivery Checklist

- [ ] Chinese timeline file created
- [ ] English timeline file created **by LLM translation**
- [ ] English SRT created
- [ ] Hard-sub video created
- [ ] Subtitle visibility verified programmatically and spot-checked
- [ ] User given final paths and short playback guidance

## Failure Modes and Remedies

1. **No subtitles visible in output**
   - Cause: missing fonts or filter fallback failure
   - Fix: provide explicit TTF + `fontsdir`, re-render, re-verify

2. **Permission denied on output**
   - Cause: current process user cannot write target path
   - Fix: run with file owner or copy from writable temp directory

3. **Timestamp drift**
   - Cause: accidental merge/split during translation
   - Fix: enforce one-to-one line mapping and re-export

4. **Terminology inconsistency**
   - Cause: unconstrained translation
   - Fix: apply terminology normalization pass before SRT generation

## What Can Be Further Improved

- Add a helper script (`scripts/verify_hardsub.py`) for automated diff checks.
- Add a helper script (`scripts/timeline_to_srt.py`) for deterministic conversion.
- Add `examples.md` with multiple domain styles (meeting, lecture, technical demo).
- Add optional bilingual subtitle mode (EN + ZH two-line display).

## Final User Response Template

- Explain what was produced and where.
- State that English translation was done by the LLM (not translation libraries).
- Confirm hard-sub verification status.
- Provide exact file paths.
- If needed, provide a short sample clip path for quick validation.
