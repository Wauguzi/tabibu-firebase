# Change Request (CRQ) — Tabibu

| Field | Value |
|---|---|
| CRQ number | CRQ-0001 |
| Title | The repository's baseline, with the server AI on Gemini |
| Requested by | Theo — CTO |
| Date raised | 2026-11-15 |
| Date implemented | 2026-11-15 |
| Priority | P2 High — see [`mobile_workflow.md` §7](../../workflow/reports/mobile_workflow.md#7-escalation--severity) |
| Change type | Normal |
| Commit(s) / PR | The baseline commits on `main`, ending with the one that adds this record |

## 1. Description of change

The baseline is the Tabibu app (patients, doctors and pathologists, from
booking to a signed result and an approved outbreak alert), its Cloud
Functions and security rules, and its docs. I committed it in batches:
tooling and CI, the app, the functions and rules, the docs, then each fix
below on its own.

What this change does:

1. **The server AI runs on Gemini.** Every Cloud Functions model call (the
   pre-read tile labels, the order risk check and notes translation, the
   symptom summary, the report translation and explanation, and the alert
   draft) goes through one injected client, `functions/src/ai-gemini.ts`,
   which calls Gemini on the Agent Platform through `@google/genai`. The
   functions authenticate as their runtime service account, so no model key
   exists anywhere. The model id and location come from the server Remote
   Config parameters `ai_text_model` (default `gemini-3.8-flash`) and
   `ai_location` (default `global`). Every call asks for JSON against a
   response schema with minimal thinking, has 60 seconds and one retry on
   429 or 503, and is checked by the same validators as before. The
   interfaces, de-identification, number checks, approvals and kill switches
   are unchanged.
2. **The server accepts no audio.** `recordSymptomTranscript` replaces
   `transcribeSymptoms`: it stores a transcript the app sends, after checking
   the caller, the switch, a daily cap and the text's shape. The
   `speechAudio/` Storage path is denied to every client. Voice input
   defaults to off in the app until speech to text runs there.
3. **Clean-up.** An unused service folder and its key and launcher targets
   are removed, and comments, test names and docs state each rule in the
   present tense, without record ids, review codes or dated notes.
4. **Fixes.**
   - A doctor who redeems a share code now lands on the case. The case
     screen used to show "not found" until the orders were refreshed by
     hand, because it fetched only when the list was empty; it now fetches
     when the case is missing and shows loading until the server answers.
     The fourth digit of the code closes the keyboard and sends it.
   - Android hosts the biometric prompt: `MainActivity` extends
     `FlutterFragmentActivity` and the launch themes inherit from AppCompat,
     as `local_auth` requires. On a plain `FlutterActivity` every biometric
     unlock failed.
   - The APK workflow pins the Flutter version `pubspec.yaml` requires,
     checks the version bump before a merge, sends testers the pull
     request's commits as release notes, and gives the build swap and
     lighter Gradle memory settings.
5. **Docs.** Every document starts on 15 November. The
   [AI service note](../../architecture/reports/ai_preread_service.md) is
   written from the code; the README, architecture, threat model, workflow
   and alert engine describe Gemini in Cloud Functions.

## 2. Business justification

Tabibu is entering a hackathon built on Firebase AI Logic and Gemini, so
its AI layer runs on Gemini, and the in-app hybrid work builds on this
baseline. The two fixes close the one gap found in testing (a shared case
that would not open) and a broken biometric unlock on Android.

## 3. Scope

**In scope:** everything in §1.

**Explicitly out of scope:**

- In-app AI calls, on device or in the cloud. They land on their own branch
  with a pull request reviewed by Greptile.
- A live run of the server jobs on Gemini. The model, the location and
  minimal thinking are taken from the documentation and the SDK, not yet
  from a live call (§9).
- An accuracy figure. The pre-read is not measured on Gemini yet, and no
  figure is quoted until an evaluation report records one.

## 4. Impact assessment

| Area | Impact | Notes |
|---|---|---|
| Data model (Firestore, Hive) | Additive | `transcriptions/{id}` gains an optional `durationBucket`; no Hive change |
| Roles & case scoping | None | `recordSymptomTranscript` is patient-only; no read or write reaches a new case |
| Clinical safety | None | No AI output reaches a person sooner. The pre-read stays the pathologist's, capped at Low, every number computed in code; approvals unchanged |
| AI service (prompts, models, thresholds) | Changed: the model and transport | Not yet evaluated on Gemini; the evaluation script runs through the same transport with `--live` |
| Security (rules, App Check, RASP, secrets) | Improved | No model key exists; `speechAudio/` is denied; no Firestore rule changed. The functions' service account needs Vertex AI User |
| Data protection (PHI, de-identification, model endpoints) | New endpoint | De-identified text and slide tiles now reach Gemini on the Agent Platform; the de-identification is unchanged and tested |
| Design system / UI consistency | None | The share-code screen keeps its layout |
| Localisation (en, sw) | None | No new strings |
| Existing data | None | Transcription documents expire after a day |

## 5. Risk & rollback plan

**Risk level:** Medium. The server jobs have not run live on Gemini.

**Rollback plan:** every AI job has a kill switch in the server Remote Config
template; turning one off stops new work within a template refresh and the
human path carries on. The functions on Gemini are not deployed yet, so
nothing live depends on them until the first deploy.

## 6. Implementation plan

1. Removed the unused service folder and its tooling.
2. Put every server model call on Gemini through `@google/genai`, behind an
   injected transport; replaced the speech callable; denied the speech path.
3. Restated comments, test names and docs as present-tense rules, without
   record ids, review codes or dated notes.
4. Fixed the share-code case, the Android biometric host and the APK
   workflow; turned voice input off by default.
5. Wrote the docs to match the code, including the AI service note.
6. Ran every gate on the exact tree committed (§7), then committed in
   batches.

**Deviation:** the workflow certifies a change on a device before it is
committed. This baseline was not run on a device: I test once the in-app AI
work is complete, before the APK goes out.

## 7. Testing & verification evidence

| Check | Result |
|---|---|
| Format check (`dart format --set-exit-if-changed`) | Pass — 1,069 files, none changed |
| `make analyze` / `make bloc-lint` | Pass — no issues; 0 bloc lint issues in 987 files |
| `flutter test` | Pass — 3,508 tests |
| `make functions-test` | Pass — lint, build and 656 emulator tests |
| `make rules-test` | Pass — 248 tests |
| `make spell` | Pass — 1,058 files |
| Release script tests | Pass — 36 tests |
| `make secrets` (gitleaks, staged) | Pass — no leaks |
| Debug APK build (development flavor) | Pass, with the biometric host and AppCompat themes |
| Model evaluation | Not run on Gemini yet (§3) |
| Manual run (device / simulator / web) | Not run (§6) |
| UI/UX review of the surrounding screen | The share-code screen and the doctor's case screen keep their layout |
| Certification | Pending the device run (§6) |

## 8. Approval

| Role | Required when | Name | Date | Decision |
|---|---|---|---|---|
| Author | Always | Theo | 2026-11-15 | — |
| Engineering reviewer | Always, on the pull request | N/A — committed directly to main | 2026-11-15 | Reviewed by me against `.greptile/rules.md` |
| Clinical Reviewer | §4 flags clinical-safety impact or changes clinical wording | Covered by CTO | 2026-11-15 | Approved: no AI output reaches a person sooner |
| Security Analyst | §4 flags security impact | Covered by CTO | 2026-11-15 | Approved |
| Compliance Officer | §4 flags data protection impact | Covered by CTO | 2026-11-15 | Approved: de-identified input only |
| Lead Designer | §4 flags design-system impact | N/A | — | — |

## 9. Post-implementation review

Open until each is done:

- ~~Grant the Cloud Functions runtime service account Vertex AI User
  (`roles/aiplatform.user`), deploy the functions, and run the pre-read
  evaluation with `--live` to confirm the model, the location and minimal
  thinking, then file an evaluation report.~~ Done 16 Nov. The grant and the
  deploy landed, and the live run confirmed the model and the location but
  not the thinking level: `gemini-3.8-flash` refuses `MINIMAL`.
  [CRQ-0003](./CRQ-0003-gemini-thinking-level.md) moved every call to `LOW`,
  and [EVAL-0001](../../testing/reports/EVAL-0001-cancer-preread-gemini-baseline.md)
  records the first figure.
- Run the app on a device and certify this baseline.
- Re-audit the threat model.

## 10. Related records

- Architecture/design references: [AI service](../../architecture/reports/ai_preread_service.md), [architecture](../../architecture/reports/mobile_architecture.md), [threat model](../../security/reports/firebase_and_ai_service_threat_model.md)
- Evaluation report(s): [EVAL-0001](../../testing/reports/EVAL-0001-cancer-preread-gemini-baseline.md)
- Related Incident Report(s): none
- Related Problem record(s): none
