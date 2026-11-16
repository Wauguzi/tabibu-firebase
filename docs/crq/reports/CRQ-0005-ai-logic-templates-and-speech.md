# Change Request (CRQ) — Tabibu

| Field | Value |
|---|---|
| CRQ number | CRQ-0005 |
| Title | Firebase AI Logic in the app: symptom transcription, the slide-region read and the narrated explanation |
| Requested by | Theo — CTO |
| Date raised | 2026-11-16 |
| Date implemented | Pending the device run on this branch |
| Priority | P2 High — see [`mobile_workflow.md` §7](../../workflow/reports/mobile_workflow.md#7-escalation--severity) |
| Change type | Normal |
| Commit(s) / PR | `feat/ai-logic-templates`; the pull request follows |

## 1. Description of change

The app gains `AiLogicService` (`lib/core/services/ai_logic_service.dart`),
on `firebase_ai` 4.0.0 with the Agent Platform backend, and three calls
through it:

- **Symptom transcription** replaces the retired server speech-to-text. The
  WAV goes, in memory, to the server prompt template
  `symptom-transcribe-v1-0-0`; the transcript comes back as JSON, the patient
  checks it, and `recordSymptomTranscript` stores it. An unclear recording or
  a blank transcript fails closed. A Swahili transcript is kept, with the
  line "Voice works best in English."
- **The slide-region read** lets the case's pathologist ask about the region
  on screen: the crop (at most 1024 px) and an optional question go to the
  template `slide-region-read-v1-0-0`, and the impression, features,
  uncertainty in words and a caveat come back in the AI frame. It is never
  saved and cannot be copied into the report.
- **Listen to this summary** reads the explanation the doctor approved aloud
  with `gemini-3.8-flash-tts`, in English or Swahili, played in the app and
  cached in memory for the screen.

The template files live in `prompts/`; the console holds each one, locked,
under the same id, and Remote Config names the ids, the TTS model and voice,
and the switches.

## 2. Business justification

The hackathon asks for Firebase AI Logic in the app. These three calls show
its server prompt templates and speech output beside the hybrid inference of
CRQ-0002, each where it helps a person: a patient who would rather speak, a
pathologist with a question about one region, a patient who would rather
listen to their result.

## 3. Scope

**In scope:** the service, the three features, their Remote Config keys and
the two templates.

**Explicitly out of scope:**

- **Switching voice and the region read on:** both ship off
  (`voice_input_enabled`, `region_read_enabled`) until a device run hears and
  reads them.
- **Limited-use App Check tokens:** wired but off (`ai_limited_use_tokens`)
  until a live call proves them on 4.0.0.
- **The narrated explanation for doctors and pathologists:** patients only.

## 4. Impact assessment

| Area | Impact | Notes |
|---|---|---|
| Data model (Firestore, Hive) | None | Nothing new is stored; the transcript uses the existing record |
| Roles & case scoping | None | The region read is gated to the case's accepted pathologist; the listen card to the patient with an approved explanation |
| Clinical safety | Reviewed | The region read is direct-use to the pathologist (S-8), AI-labelled, never saved; the narration is approved text, unchanged |
| AI service (prompts, models, thresholds) | Added | Two templates; the TTS model `gemini-3.8-flash-tts` |
| Security (rules, App Check, RASP, secrets) | Affected | Three client calls under AI Logic's App Check, authenticated users and quota (T-21) |
| Data protection (PHI, de-identification, model endpoints) | New endpoint | The patient's recorded voice cannot be de-identified (T-24); it is held in memory for one call, never uploaded |
| Design system / UI consistency | Existing pattern | `AiDraftFrame`, `ListenCard`, the settled sheet |
| Localisation (en, sw) | Added | The listen, region-read and Swahili-voice strings in both ARB files |
| Existing data | None | |

## 5. Risk & rollback plan

**Risk level:** Medium. Three new calls from the client, one carrying a
patient's voice.

**Rollback plan:** `voice_input_enabled`, `region_read_enabled` and
`explanation_listen_enabled` hide each one without a release. Reverting the
branch removes the service.

## 6. Implementation plan

1. `AiLogicService` and the transcription path (bundle 03), then the region
   read and the listen card (bundle 04), each reviewed in two rounds.
2. The transcription template created, tested with synthetic speech, and
   locked in the console; the client Remote Config keys published.
3. The region template after review, the same way.
4. The device run, then the pull request.

## 7. Testing & verification evidence

| Check | Result |
|---|---|
| `make analyze` / `make bloc-lint` | Pass — no issues |
| `make test` (`TZ=UTC`) | Pass — the full suite |
| iOS resolve | `firebase-ios-sdk` stays 12.19.3 after a real Xcode resolve; the hybrid pin holds |
| Transcription template | Console test with synthetic English speech returned the sentence verbatim, `language: "en"`, `unclear: false` |
| TTS format | A live call returned `audio/wav` with a RIFF header, in English and in `sw` |
| Red proofs | Fail-closed parsing, no upload, consent before the first recording, approved-only listening, cache hit, the region switch, a doctor never seeing the region read |
| Manual run | Pending |
| Certification | Pending |

## 8. Approval

| Role | Required when | Name | Date | Decision |
|---|---|---|---|---|
| Author | Always | Theo | 2026-11-16 | — |
| Engineering reviewer | Always, on the pull request | Greptile — pending | — | — |
| Clinical Reviewer | §4 flags clinical-safety impact or changes clinical wording | Covered by CTO | 2026-11-16 | Approved: direct-use only to the pathologist, AI-labelled, never saved |
| Security Analyst | §4 flags security impact | Covered by CTO | 2026-11-16 | Approved: T-21 and T-24 |
| Compliance Officer | §4 flags data protection impact | Covered by CTO | 2026-11-16 | Approved: the voice path is consented, off by default and kept in memory |
| Lead Designer | §4 flags design-system impact | N/A | — | — |

## 9. Post-implementation review

Filled in after the device run.

## 10. Related records

- Architecture/design references: [AI service §9](../../architecture/reports/ai_preread_service.md#9-in-the-app-templates-and-speech), [threat model](../../security/reports/firebase_and_ai_service_threat_model.md) (S-5, S-8, T-21, T-24)
- Evaluation report(s): none; no model figure is quoted
- Related Incident Report(s): none
- Related Problem record(s): none
