# Model Evaluation Report (EVAL) — Tabibu

| Field | Value |
|---|---|
| Report ID | EVAL-0001 |
| Profile | Cancer |
| Date | 2026-11-16 |
| Service commit | The CRQ-0003 change on `fix/gemini-thinking-level` |
| Related CRQ | [CRQ-0003](../../crq/reports/CRQ-0003-gemini-thinking-level.md) |
| Previous report | Baseline |

## 1. What changed

This is the first measurement of the cancer pre-read on Gemini. The first
live call failed: `gemini-3.8-flash` refuses the `MINIMAL` thinking level
the transport asked for. CRQ-0003 moved every server call to `LOW`, and
these numbers come from the run after that fix.

Each tile goes through the worker's own request builder and answer checks
(`buildClassifyRequestBody`, `parseClassifyTiles`), one tile per request as
in production. A first run used a request the script built itself, without
the few-shot instruction or the check that refuses an example's id; it
scored 74% sensitivity and 81% specificity, inside these intervals, and is
superseded.

## 2. Setup

| Item | Value |
|---|---|
| Dataset | PatchCamelyon, 96 px H&E tiles ([`KE9037/PatchCamelyon`](https://huggingface.co/datasets/KE9037/PatchCamelyon), revision `2f67f00`) |
| Sample | The fixed held-out set, `functions/data/eval_pcam/`: 200 tiles from the dataset's test split, staged by `stage-pcam.ts`; never used for tuning |
| Class balance in sample | 100 Tumour / 100 Normal |
| Models and versions | `gemini-3.8-flash` on the Agent Platform, location `global`, thinking `LOW` |
| Prompt version | `preread-classify-v4`, four labelled few-shot examples, one tile per request, no upscale; the request and answer checks the worker uses |
| Decision threshold | The model's label; no threshold is applied to its stated probability |
| Command | `GCLOUD_PROJECT=tabibu-86ea2 npx ts-node scripts/eval-preread.ts --live` (from `functions/`) |
| Cost | About $0.40 a run, the script's estimate; two runs; not a billed figure |

## 3. Results

| Metric | Value | 95% CI | Previous |
|---|---|---|---|
| Sensitivity (recall on positives) | 70.0% (70/100) | 60.4–78.1% | — |
| Specificity | 79.0% (79/100) | 70.0–85.8% | — |
| Positive predictive value | 76.9% (70/91) | 67.3–84.4% | — |
| Negative predictive value | 72.5% (79/109) | 63.4–80.0% | — |
| Confusion matrix (TP / FP / FN / TN) | 70 / 21 / 30 / 79 | — | — |
| Low-confidence rate | 100%: every model run is capped at Low ([AI service §3.2](../../architecture/reports/ai_preread_service.md#32-confidence)) | — | — |
| Sensitivity outside the low-confidence band | Not applicable: no tile is outside it | — | — |
| Time to preliminary report (median / p90, seconds) | Not measured. Mean model latency was 7.3 s a tile; a 64-tile run at four calls at a time is about 120 s, inside the worker's 240 s | — | — |

Accuracy was 74.5% (149/200, 68.0–80.0%). Intervals are Wilson score.

## 4. Error analysis

The script records only the summary, not each tile, so I cannot list the 30
false negatives and 21 false positives by id. One result stands out anyway:
all 200 answers carried a high stated probability, and 25.5% of them were
wrong, which is every one of the 51 errors. The stated probability carries no
information about whether a label is right, which is why §3.2 caps every
model run at Low. No false negative is outside the low-confidence band,
because there is nothing outside it.

## 5. Limitations

- **Tiles, not slides.** A 96 px tile is not a slide; a missed tile may sit
  beside detected ones in the same focus. Slide-level sensitivity is not
  measured.
- **A public dataset, not local samples.** PatchCamelyon comes from lymph
  node sections scanned in the Netherlands. Staining, scanners and tissue in
  Kenyan laboratories differ, and nothing here was measured on them.
- **One run of 200 tiles.** The intervals are wide; a difference smaller
  than them is no measurable change.
- **No pathologist review.** The reference labels are the dataset's, and no
  pathologist read these tiles or the drafts built from them.

## 6. Decision

Adopt as the baseline. About three tumour tiles in ten are missed, so the
pre-read remains a prompt for the pathologist and never a reading: every
case is still read and signed by its pathologist (S-1), the confidence stays
capped at Low, and a Low draft moves up the worklist. The figure goes in the
AI service note §3.3 and is quoted nowhere else without this report.

## 7. Sign-off

| Role | Name | Date | Decision |
|---|---|---|---|
| CTO / Mobile Engineer | Theo | 2026-11-16 | Adopted as the baseline |
| Clinical Reviewer | Covered by CTO until filled | 2026-11-16 | Approved: the pre-read stays a prompt, capped at Low |
