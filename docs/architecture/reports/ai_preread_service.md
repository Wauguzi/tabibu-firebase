# Tabibu — AI Service & Pre-read Pipeline

> Where Tabibu calls a model, what each call may see, and what happens to its
> output. AI prepares and a person decides. Pair it with
> [`mobile_architecture.md`](./mobile_architecture.md) §3 for the layering and
> [`outbreak_alert_engine.md`](./outbreak_alert_engine.md) for alert drafting,
> whose detector is code, not a model.

| Field | Value |
|---|---|
| Owner | Theo — CTO, Mobile Engineer |
| Status | Server jobs built on Gemini; two in-app tasks on the device's own model, one with a cloud fallback (§8) |
| Last reviewed | 2026-11-15 |
| Runs on | Cloud Functions (`functions/src`), calling Gemini on the Agent Platform through `@google/genai` (`ai-gemini.ts`) |
| Credentials | None stored. The Functions runtime service account holds Vertex AI User (`roles/aiplatform.user`) and the SDK uses Application Default Credentials |
| Writes to | Firestore `cases/{caseUid}/preread/{runUid}` and the job records in §1; Storage `preread/{caseUid}/{runUid}/` |

## 1. Jobs

| Job | Trigger | Model input | Output | Who sees it first |
|---|---|---|---|---|
| **Pre-read** | A case with slide images is assigned to a pathologist | One 96 px tile per request, with four labelled examples | A label per tile; the measurements and the draft are computed in code (§3) | The case's pathologist only (S-1) |
| **Order risk check and notes translation** | A doctor submits an order, or edits its notes while they are editable | The de-identified notes and the order | Suggested tests, a protocol advisory from a fixed template, and the notes in the other language, from **one call** | The ordering doctor; the translation also the pathologist, beside the original |
| **Symptom summary** | A patient books with typed symptoms | The de-identified symptom text | A structured summary in English and Swahili from one call | The doctor who takes the appointment |
| **Report translation** | A version is signed | The signed, de-identified text | The report in the other language | The signer, who approves it before any reader sees it |
| **Patient explanation** | The doctor marks a result discussed | The signed, de-identified text | A plain-language explanation in English and Swahili | The ordering doctor, who approves it before the patient sees it |
| **Alert drafting** | The detector raises a signal | Disease, county, rule and the bundled guidance; no case data and no numbers | Doctor guidance and a patient notice in en and sw, with placeholders | The alert approver. If the model fails, a fixed template draft is used |

**Speech.** Voice input for symptoms is off (`voice_input_enabled`). The
server accepts no audio: `recordSymptomTranscript` stores a transcript the
app sends, checked for the caller, the switch, a daily cap and its shape, and
the booking links it. Chat voice notes are recorded and played and never sent
to a model; their transcript is marked `Failed` with `UnsupportedFormat`.

Every output is written to Firestore for a person to act on; none goes to
anyone directly. **Where the docs require an approval, it is a one-tap
"approve as is"**, with editing secondary: the pre-read (scored, then signed),
the report translation (the signer), the patient explanation (the ordering
doctor) and an alert (an authorised clinician holding the approver
permission). **Where the threat model's S-8 names the reader as the qualified
person who acts on the output, it is used directly**: the symptom summary and
risk advice to the doctor, the notes translation to the doctor and
pathologist, and the in-app notes summary to the doctor who wrote the notes
(§8). Either way the output is labelled as AI, and its input is
de-identified (S-5), except the two in-app tasks §8 names. Server outputs
record their signals (§6).

## 2. Invocation

```
App write ──► Firestore ──► Cloud Function trigger ──► Gemini (Agent Platform, ADC)
                               (checks state and its kill switch,     │
                                sets status=Queued, de-identifies)    │
                                                                      ▼
App listens ◄── Firestore ◄── Admin SDK write (status=Ready|Failed) ◄─┘
```

- The trigger owns the state change to `Queued` and passes only ids, Storage
  paths and de-identified text. Free text goes as data, never as
  instructions (T-12).
- Every call asks for JSON against a response schema, at the lowest
  thinking level the model accepts (`LOW`: `gemini-3.8-flash` refuses
  `MINIMAL`), and the existing validator checks the answer before anything
  is stored. A call has 60 seconds and one retry on 429 or 503. A timeout, a
  service error or an answer off the schema writes `Failed` with a
  `failureReason`, and is never thrown back into the trigger's retry loop.
- A pre-read still `Queued` or `Running` 30 minutes after it was requested is
  failed as `Stale` by the sweep, and the case moves on to a manual read.
- Rules deny client writes to every `preread` document and job record.
- The model id and location come from the server Remote Config parameters
  `ai_text_model` and `ai_location`, with in-code fallbacks, so a model can
  change without a deploy.

## 3. The pre-read pipeline

The specimen type on the order selects a **profile**: cancer (PatchCamelyon
H&E tiles) or malaria (thin-smear cells).

| Step | What does it |
|---|---|
| **1. Label** | Gemini, one tile per request with four labelled CC0 examples, at most 64 tiles a run. Results are cached by model id, prompt version and image hash, so an unchanged re-run costs nothing |
| **2. Measure** | Code (`preread-measure.ts`): the heatmap, the largest tumour focus and its micro- or macro-metastasis class, or parasitised cells and parasitemia |
| **3. Draft** | Code: the structured draft is composed from the measurements and the labels |
| **4. Check** | Code: every number in the draft must match the measurement record, or the run fails as `NumberCheck` |
| **5. Rank** | Code: worklist priority from urgency, risk flags and confidence (`rankCase`) |

There is no segmentation model: the heatmap is composed from tile labels.

### 3.1 Measurement is code

Every number the report shows comes from step 2 (S-6). Physical size needs
the slide's micrometres per pixel, stored with each image at upload; a tile
without it gets no size claim.

### 3.2 Confidence

The model's stated probabilities are not calibrated, so every model run's
confidence band is **capped at Low**. A Low-confidence draft moves **up** the
worklist for a careful read, and the label is shown wherever the draft is.
The pre-read is a prompt for the pathologist, not a reading.

### 3.3 Accuracy

The held-out evaluation (`functions/scripts/eval-preread.ts`, the same
transport with `--live`) ran on 200 PatchCamelyon test tiles on 16 Nov
([EVAL-0001](../../testing/reports/EVAL-0001-cancer-preread-gemini-baseline.md)):
sensitivity 74% (95% CI 64.6–81.6%) and specificity 81% (72.2–87.5%), per
tile. Every wrong label came with a high stated probability, which is why
§3.2 caps the band at Low. No other figure is quoted.

## 4. Review and signing

1. The pathologist opens the case; the viewer shows the image with the
   heatmap overlaid, and each finding links to its tiles.
2. **The pathologist scores the pre-read before writing.** The primary action
   is a one-tap "Agree with the pre-read"; each verdict can be changed.
3. Relabelling a tile recalculates the measurements at once. The server's
   measurement functions are authoritative; the app's Dart port is kept in
   step by a shared fixture suite.
4. **Sign** calls `signReport`, which recomputes the measurements from the
   final labels and writes, in one transaction, the signed version, the
   untouched AI draft beside it and the field-level diff. It refuses a draft
   that changed since the pathologist last saw it, and a replay returns the
   version already signed. Only a signed report is readable by the doctor.

**Texts that follow a signed report** (translation, explanation) live in a
working record that only their approver reads. Approval creates a separate
reader-facing record holding the approved text alone, so readers never
receive unapproved model text. A text with a number that is not in the
signed report fails as `NumberCheck`, and an approval whose edit changes a
number is refused.

## 5. Firestore contract

`cases/{caseUid}/preread/{runUid}`, complete at creation:

| Field | Type | Notes |
|---|---|---|
| `uid`, `caseUid`, `profile` | string | `profile`: `Cancer` / `Malaria` |
| `status` | string | `Queued` → `Running` → `Ready` / `Failed`; gates every other field |
| `imagePaths` | string[] | Storage paths; never a public URL |
| `micronsPerPixel` | number | `0` means unknown, so no size claim |
| `segmentationPath`, `labelsPath` | string | The heatmap and the tile labels, as JSON files in Storage |
| `labelCounts` | map | label → count |
| `measurements` | map | Profile-specific; every value computed in code |
| `draft` | map | Findings, impression, confidence band, urgency, next steps |
| `models` | map | Model id per step |
| `inputLanguage` | string | The language of the doctor's notes |
| `requestedAt`, `startedAt`, `readyAt` | string (UTC) | `readyAt − requestedAt` is time to preliminary report |
| `failureReason` | string | `''` unless `Failed`: `Timeout`, `ServiceError`, `OffSchema`, `NumberCheck`, `Stale`, `Disabled` |
| `lastUpdatedAt` | string (UTC) | |

The order's records are `riskCheck/current` (suggested test ids, the
advisory key and its template text, `models`, `failureReason`) and
`notesTranslation/current` (the text, its languages and a `sourceSha256` of
the notes, so the app shows nothing once the notes change).

## 6. Data policy

- **Only ids, images and de-identified text reach a model** (no name, phone,
  exact location or date of birth). The server accepts no audio.
- **Diagnostic images are always the real sample**, never generated or
  altered.
- **Every model output is stored** beside what the person did with it, and
  every approval records `acceptedUnchanged`, plus the edit distance or field
  diff when it was edited.
- **Model performance signals**: counts, rates, durations, language codes and
  model ids, never a uid, a name or text. `aggregateModelSignals` writes them
  daily to `modelSignals/{YYYYMMDD}`, which only admins read.

## 7. Kill switches

Remote Config, read by the triggers and by the app: `preread_enabled`,
`risk_check_enabled`, `patient_explanations_enabled`,
`report_translation_enabled`, `symptom_intake_enabled`,
`voice_input_enabled`, `alert_drafting_enabled` and `alerts_delivery_enabled`.
Turning one off stops new work and hides the surface; it deletes nothing
stored. When the server template cannot load, every AI-job switch fails
closed (no new job; the human path continues) and alert drafting falls back
to the template draft, so the approver still gets one.

## 8. In the app: hybrid inference

Two short tasks run in the app through Firebase AI Logic's native hybrid
SDKs, bridged to Flutter over `MethodChannel("tabibu/hybrid_ai")`. The
prompts live in the native plugins, so Dart can only name a task.

| Task | Who | Model | Output |
|---|---|---|---|
| **Symptom tidy** (`symptom_tidy`) | The patient, booking | The device's model first, Gemini in the cloud when there is none | A tidier version of their own text, labelled as AI, replacing it only after "Use this" |
| **Notes summary** (`notes_summary`) | The doctor, ordering | The device's model only (`ONLY_ON_DEVICE`) | Three bullets in the AI frame, never written into the notes the order stores |

- **The notes never leave the device.** The iOS bridge builds no cloud model
  for a notes summary, whatever mode arrives, and the action hides when the
  device has no model.
- **A tidy may reach the cloud**, so the app strips phone numbers and email
  addresses before any tidy request leaves Dart. The patient's own words are
  the named exception in the threat model's S-8.
- **Both actions show where they ran** ("On this phone" or in the cloud) and
  hide in Kiswahili, for text that is not English, or when switched off
  (`hybrid_symptom_tidy_enabled`, `hybrid_notes_summary_enabled`).
- **Both actions hide where no bridge exists** (the web, desktop): a missing
  plugin reads as `unsupported`, which hides both tasks with no reason text.
- **The status is read again when the app returns to the foreground**, so a
  model that became ready while the app was away shows its action. A refresh
  never disturbs a running or proposed state.
- Nothing logged includes the input or the output.

## 9. Change log

| Date | Change | Author |
|---|---|---|
| 2026-11-15 | Crafted for this repository. | Theo |
