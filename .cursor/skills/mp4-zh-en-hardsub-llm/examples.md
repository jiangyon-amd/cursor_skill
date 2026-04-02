# Examples

## Example 1: End-to-End on `Use_AI.mp4`

Input:
- `/workspace/Use_AI.mp4`

Run:

```bash
bash "/workspace/.cursor/skills/mp4-zh-en-hardsub-llm/scripts/run_pipeline.sh" \
  --input "/workspace/Use_AI.mp4" \
  --outdir "/workspace" \
  --basename "Use_AI" \
  --whisper-model "small"
```

The script will:
1. Extract audio to `/workspace/Use_AI_zh.wav`
2. Transcribe Chinese timeline to `/workspace/Use_AI_zh_timeline.txt`
3. Stop and request LLM translation for `/workspace/Use_AI_en_timeline.txt` (manual LLM step)
4. Continue to generate SRT, hard-sub video, and verification report once English timeline exists

Manual LLM translation requirement:
- Translate `/workspace/Use_AI_zh_timeline.txt` to `/workspace/Use_AI_en_timeline.txt`
- Preserve timestamps and line count
- Use terminology policy from `SKILL.md`

Resume after LLM translation:

```bash
bash "/workspace/.cursor/skills/mp4-zh-en-hardsub-llm/scripts/run_pipeline.sh" \
  --input "/workspace/Use_AI.mp4" \
  --outdir "/workspace" \
  --basename "Use_AI" \
  --whisper-model "small"
```

Expected outputs:
- `/workspace/Use_AI_zh.wav`
- `/workspace/Use_AI_zh_timeline.txt`
- `/workspace/Use_AI_en_timeline.txt` (LLM-generated)
- `/workspace/Use_AI.en.srt`
- `/workspace/Use_AI_with_en_hardsub.mp4`
- `/workspace/Use_AI_hardsub_verify.json`

## Example 2: Resume in Offline/Restricted Network Mode

If ASR model download is blocked but Chinese timeline already exists:

```bash
bash "/workspace/.cursor/skills/mp4-zh-en-hardsub-llm/scripts/run_pipeline.sh" \
  --input "/workspace/Use_AI.mp4" \
  --outdir "/workspace" \
  --basename "Use_AI" \
  --skip-asr
```

This mode requires:
- `/workspace/Use_AI_zh_timeline.txt` exists
- `/workspace/Use_AI_en_timeline.txt` exists (LLM-translated)

## Example 3: Verify Existing Hard-Sub Video

```bash
python3 "/workspace/.cursor/skills/mp4-zh-en-hardsub-llm/scripts/verify_hardsub.py" \
  --source "/workspace/Use_AI.mp4" \
  --hardsub "/workspace/Use_AI_with_en_hardsub.mp4" \
  --timestamp 5.0 \
  --out "/workspace/Use_AI_hardsub_verify.json"
```

Pass criteria:
- `nonzero_bottom_pixels > 1000`
- `bottom_mean_diff > 1.0`
