# Search inside videos — feasibility

Reference idea: [ssrajadh/sentrysearch](https://github.com/ssrajadh/sentrysearch)
(natural-language search over video footage). This note covers how the same
feature fits Kader; it is not a port of that project.

## Verdict

Feasible, and most of the pieces already exist. Kader's visual search embeds
images and text into one space with Qwen3-VL-Embedding (llama.cpp, on-device).
A video becomes searchable by embedding **sampled frames** and searching them
like photos, then returning the **timestamp** so the viewer seeks to the moment.

## Design

1. **Frame sampling** (worker thread, background priority): one frame every
   N seconds (N = 2 for clips under 1 min, 5 for longer, at most ~240 frames
   per video), plus scene-change frames (`ffmpeg -vf "select='gt(scene,0.3)'"`).
   Frames are decoded at 512 px. ffmpeg is already a runtime dependency.
2. **Deduplicate** near-identical consecutive frames (cosine > 0.97) so static
   shots don't flood the index.
3. **Store** in a new table:
   `video_frames(media_id, t_ms, embedding BLOB, model_ver)`.
4. **Search**: the query embedding is scored against photos and frames in one
   pass; frames are grouped per video (best frame wins) and shown as
   "Visual matches" with a timestamp badge. Opening one seeks the player to
   `t_ms` minus 1.5 s.
5. **Cost**: ~0.3–0.6 s per frame on a recent CPU (2B model, 512 px), so a
   1-minute clip at 2 s spacing is ~15 s of background work. This should be
   opt-in per library ("Index video content"), with the same resource budget
   as photo indexing.

## What's missing today

- frame extraction + the `video_frames` table (small);
- timestamp-aware result items and a `seek` property on the viewer (small);
- an opt-in toggle in Settings → AI (small).

Audio and speech search (Whisper-style transcripts) would be a separate,
larger feature; it's not required for visual moments.
