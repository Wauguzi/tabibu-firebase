# Change Request (CRQ) — Tabibu

| Field | Value |
|---|---|
| CRQ number | CRQ-0003 |
| Title | Server Gemini calls think at LOW, the lowest level the model accepts |
| Requested by | Theo — CTO |
| Date raised | 2026-11-16 |
| Date implemented | 2026-11-16 |
| Priority | P2 High — see [`mobile_workflow.md` §7](../../workflow/reports/mobile_workflow.md#7-escalation--severity) |
| Change type | Normal |
| Commit(s) / PR | [PR #16](https://github.com/Wauguzi/tabibu-firebase/pull/16), merged to `main` as `bb66132` on 2026-11-16; the fix is `546152b`, the evaluation path `af474a8` |

## 1. Description of change

Every server call to Gemini asked for the `MINIMAL` thinking level, and
`gemini-3.8-flash` refuses it with `INVALID_ARGUMENT` ("Thinking level is
unsupported"). The first live call, the held-out evaluation on 16 Nov, found
it. Every server AI job would have failed as `ServiceError`: the pre-read,
the risk check and notes translation, the symptom summary, the report
translation and the patient explanation. Alert drafting would have fallen
back to its template.

The transport's constant is now `GEMINI_THINKING_LEVEL = ThinkingLevel.LOW`
(`functions/src/ai-gemini.ts`), and the pre-read tiles share it. The
evaluation script's live run follows the constant. Its tuning variants that
named `MINIMAL` now use `LOW`; the two that then duplicated existing `LOW`
variants are removed.

## 2. Business justification

The pre-read is the reason Tabibu exists, and the live demo would never have
produced one. CRQ-0001 §9 asked for a live evaluation to confirm the model,
the location and the thinking level before quoting anything; this is that
confirmation, and it found the one setting that was wrong.

## 3. Scope

**In scope:** the thinking level of every server Gemini call, its tests,
the evaluation script, and the docs that described "minimal thinking".

**Explicitly out of scope:**

- Tuning the prompt or the thinking level for accuracy: `LOW` is chosen
  because it is the cheapest level the model accepts, not because it scored
  best. The tuning set is where any change is tried, never the held-out set.
- The in-app hybrid calls (CRQ-0002), which set no thinking level.

## 4. Impact assessment

| Area | Impact | Notes |
|---|---|---|
| Data model (Firestore, Hive) | None | The pre-read cache key does not include the thinking level, and no `MINIMAL` call ever succeeded, so nothing is cached under it |
| Roles & case scoping | None | |
| Clinical safety | None | No gate changes: the pre-read is still scored and signed by its pathologist, and its confidence stays capped at Low |
| AI service (prompts, models, thresholds) | Changed | Thinking level `MINIMAL` → `LOW` for every server call; model, prompts and schemas unchanged. First held-out figure: [EVAL-0001](../../testing/reports/EVAL-0001-cancer-preread-gemini-baseline.md) |
| Security (rules, App Check, RASP, secrets) | None | |
| Data protection (PHI, de-identification, model endpoints) | None | Same endpoint, same de-identified input |
| Design system / UI consistency | None | |
| Localisation (en, sw) | None | |
| Existing data | None | No job succeeded under `MINIMAL`; the function logs from the 16 Nov deploy to this change show the AI triggers starting and never invoked |

## 5. Risk & rollback plan

**Risk level:** Low. One constant, the level the live call proved the
model accepts. `LOW` uses somewhat more tokens and time than `MINIMAL`
would have; the evaluation measured a mean of 7.3 s a tile, so a 64-tile
run fits the worker's 240 s.

**Rollback plan:** revert the change and redeploy the functions. Rolling
back restores a level the model refuses, so the kill switches
(`preread_enabled` and the others in [AI service §7](../../architecture/reports/ai_preread_service.md#7-kill-switches))
are the way to stop the jobs instead.

## 6. Implementation plan

1. Probe the model: one short call per thinking level to
   `gemini-3.8-flash` in `global`. `MINIMAL` was refused; `LOW`, `MEDIUM`,
   `HIGH` and no setting were accepted.
2. Move the constant to `LOW`, rename it so its name stops claiming
   "minimal", and point the pre-read tiles at it.
3. Update the tests that asserted `MINIMAL`; add one that fails if any
   server call asks for it again.
4. Move the evaluation script's variants off `MINIMAL`, and score single
   tiles through the worker's request builder and answer checks, as
   production sends them (Greptile round 1).
5. Run the held-out evaluation through the fixed transport and file
   EVAL-0001.
6. Deploy the functions ahead of the merge, because the live demo produced
   no pre-read until they were, then certify with a pre-read on a device.

## 7. Testing & verification evidence

| Check | Result |
|---|---|
| `make fmt` | N/A — no Dart changed |
| `make analyze` / `make bloc-lint` | N/A — no Dart changed |
| `make functions-test` | Pass — 657 tests; with the constant set back to `MINIMAL`, 5 fail, including the new guard |
| Functions lint, build, type-check | Pass |
| Rules tests | N/A — no rules changed |
| Model evaluation | [EVAL-0001](../../testing/reports/EVAL-0001-cancer-preread-gemini-baseline.md): 200 held-out tiles through the worker's request builder, none refused; sensitivity 70%, specificity 79% |
| Manual run | Pass — 16 Nov, on an iPhone 14 with the seeded accounts: a doctor's histopathology order with 2 slides, accepted by the pathologist; the pre-read went `Ready` in 2 min 43 s (45 tiles: 33 Normal, 12 Tumour), confidence capped at Low, no model call refused |
| UI/UX review | N/A |
| Certification | 2026-11-16, Theo |

## 8. Approval

| Role | Required when | Name | Date | Decision |
|---|---|---|---|---|
| Author | Always | Theo | 2026-11-16 | — |
| Engineering reviewer | Always, on the pull request | Greptile — [PR #16](https://github.com/Wauguzi/tabibu-firebase/pull/16) | 2026-11-16 | 5/5 — Approved after one round |
| Clinical Reviewer | §4 flags clinical-safety impact or changes clinical wording | N/A | — | — |
| Security Analyst | §4 flags security impact | N/A | — | — |
| Compliance Officer | §4 flags data protection impact | N/A | — | — |
| Lead Designer | §4 flags design-system impact | N/A | — | — |

## 9. Post-implementation review

Why the tests did not catch it: they run against a fake transport and
asserted the setting the code chose, which proves the code is consistent,
not that the model accepts it. Only a live call could, and CRQ-0001 named
that gap ("taken from the documentation and the SDK, not yet from a live
call"). The evaluation now runs live before any figure is quoted.

**Greptile round 1 (16 Nov) on PR #16.** 4/5, one P2 finding, fixed on this
branch: the evaluation scored single tiles with a request it built itself,
without the worker's few-shot instruction or its check that refuses an
example's id, so the baseline did not measure production's request. Every
tile now goes through `classifyBatch`, which calls the worker's
`buildClassifyRequestBody` and `parseClassifyTiles`, one tile per request
as production sends it. The rerun, 70% sensitivity and 79% specificity, is
inside the first run's intervals and replaces it in EVAL-0001.

**After the merge (16 Nov).** Greptile scored 5/5 on the second review. The
device run that certifies the change took 2 min 43 s from start to `Ready`
for 45 tiles, slower than EVAL-0001's latency suggests for a 64-tile run
(about 2 min) but inside the worker's 240 s. A 64-tile run is measured before
the demo; if it approaches 240 s, the batch concurrency is the lever, not
the thinking level.

## 10. Related records

- Architecture/design references: [AI service §2](../../architecture/reports/ai_preread_service.md#2-invocation), [§3.3](../../architecture/reports/ai_preread_service.md#33-accuracy)
- Evaluation report(s): [EVAL-0001](../../testing/reports/EVAL-0001-cancer-preread-gemini-baseline.md)
- Related Incident Report(s): none; no request reached the broken setting
- Related Problem record(s): CRQ-0001 §9, the live check it left open
