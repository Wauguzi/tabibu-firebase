# Change Request (CRQ) — Tabibu

| Field | Value |
|---|---|
| CRQ number | CRQ-0002 |
| Title | Hybrid inference in the app: an on-device symptom tidy and notes summary |
| Requested by | Theo — CTO |
| Date raised | 2026-11-15 |
| Date implemented | Pending: the device runs (§7) |
| Priority | P2 High — see [`mobile_workflow.md` §7](../../workflow/reports/mobile_workflow.md#7-escalation--severity) |
| Change type | Normal |
| Commit(s) / PR | `feat/hybrid-bridge`; the pull request once Android lands |

## 1. Description of change

Two short AI tasks run in the app through Firebase AI Logic's native hybrid
SDKs, bridged to Flutter over `MethodChannel("tabibu/hybrid_ai")`:

- **Symptom tidy** (patient, booking): the device's model first, Gemini in
  the cloud when there is none. The tidier text appears in the AI frame with
  where it ran, and replaces the patient's text only on "Use this".
- **Notes summary** (doctor, ordering): the device's model only. Three
  bullets in the AI frame, never written into the notes the order stores.

Dart names a task (`symptom_tidy` or `notes_summary`); the prompts live in
the native plugins, so the app cannot run an arbitrary prompt. On iOS the
bridge uses `FirebaseAILogic` 12.19.3, pinned exactly: a `HybridModel` (the
system model, then Gemini) for a tidy on iOS 26 and later, the cloud model
below 26, and the system model alone for a summary, with no cloud model
built. The source shown comes from the response's model version. Both
actions hide when switched off (`hybrid_symptom_tidy_enabled`,
`hybrid_notes_summary_enabled`), in Kiswahili, for text that is not English,
and when no model can run.

Before a tidy leaves Dart, `HybridRequest.toMap()` replaces email addresses
and Kenyan phone numbers with placeholders, using the server
de-identifier's patterns.

## 2. Business justification

The hackathon judges hybrid inference: on-device where a model exists, the
cloud otherwise. Both tasks fit Tabibu's offline-first design. A patient can
tidy their own words before booking without a signal, and a doctor can
check their notes at a glance while ordering, without the notes leaving the
phone.

## 3. Scope

**In scope:** the Dart contract, bloc and actions; the iOS bridge; the
Android plugin; the contact-detail stripping; the docs and threat model
for in-app model calls.

**Explicitly out of scope:**

- Kiswahili for either task: the on-device models are offered in English,
  and the actions hide in Kiswahili.
- The cloud features through server prompt templates (speech to text, the
  spoken explanation, the slide-region question): their own branch.
- An app-triggered model download or warm-up: the features never need one.

## 4. Impact assessment

| Area | Impact | Notes |
|---|---|---|
| Data model (Firestore, Hive) | None | Nothing is stored: a tidy changes a text field only on "Use this", and a summary is never stored |
| Roles & case scoping | None | Each task reads only text the person is typing |
| Clinical safety | Reviewed | Output is labelled as AI with where it ran. A tidy is the patient's own words, applied only on their tap; a summary is read by the doctor who wrote the notes and is never stored. The prompts forbid adding facts, diagnosing or advising (T-22) |
| AI service (prompts, models, thresholds) | Added | Two native prompts, the same on both platforms; cloud fallback `gemini-3.5-flash-lite` (`hybrid_cloud_model`) |
| Security (rules, App Check, RASP, secrets) | Affected | In-app calls rely on App Check enforcement, authenticated users and a per-user quota on AI Logic (T-21); no key in the app |
| Data protection (PHI, de-identification, model endpoints) | New endpoint | A tidy may reach Gemini in the cloud, after contact details are stripped: the named S-8 exception. Notes never leave the device. Monitoring logs are excluded (T-23) |
| Design system / UI consistency | Existing pattern | `AiDraftFrame` with a source chip |
| Localisation (en, sw) | Added | Nine `hybrid*` strings in both ARB files; the actions hide in Kiswahili, so the Kiswahili copy shows only in reasons |
| Existing data | None | |

## 5. Risk & rollback plan

**Risk level:** Medium. A new endpoint from the client, and a model on the
device whose quality has not been checked on real phones yet. Android's
minimum rises to API 26, the on-device floor, which drops Android 7.0 and
7.1.

**Rollback plan:** `hybrid_symptom_tidy_enabled` and
`hybrid_notes_summary_enabled` in Remote Config hide each action without a
release; reverting the branch's commits removes the bridge.

## 6. Implementation plan

1. Dart contract, bloc and actions, run against a fake service.
2. iOS bridge on `FirebaseAILogic` 12.19.3, wired to the Dart contract.
3. Contact details stripped from every tidy request; the S-8 exception, the
   threat model and the docs updated.
4. Android plugin on the same contract and prompts; an answer cut off at
   the 200-token cap is refused, so "Use this" never applies part of one.
5. The hybrid copy into both ARB files; a summary's button reads Done.
6. Gradle 9.5.0, AGP 9.3.1 and Kotlin 2.4.20, the minimums Flutter asks
   for; built-in Kotlin waits for FlutterFire (architecture §16 item 12).
7. Device runs, then the pull request.

## 7. Testing & verification evidence

| Check | Result |
|---|---|
| `make analyze` / `make bloc-lint` | Pass |
| Hybrid and screen tests | Pass — 254, including the stripping tests |
| iOS RunnerTests (simulator) | Pass — 4: source and status mapping, the routing matrix, the prompts; run on one named simulator |
| iOS simulator build | Pass |
| Android plugin | Pass — compiles; 5 JVM contract tests (routing, cut-off, failure codes); debug APK builds on the upgraded toolchain |
| Manual run | Pending: on-device in airplane mode on an Apple Intelligence device; cloud fallback on the iPhone 14; a physical Android phone |
| Certification | Pending |

## 8. Approval

| Role | Required when | Name | Date | Decision |
|---|---|---|---|---|
| Author | Always | Theo | 2026-11-15 | — |
| Engineering reviewer | Always, on the pull request | Greptile — pending | — | — |
| Clinical Reviewer | §4 flags clinical-safety impact or changes clinical wording | Covered by CTO | 2026-11-15 | Approved: AI-labelled, applied only on the person's tap, never stored |
| Security Analyst | §4 flags security impact | Covered by CTO | — | Pending the console steps (T-21, T-23) |
| Compliance Officer | §4 flags data protection impact | Covered by CTO | 2026-11-15 | Approved: the S-8 exception, with contact details stripped |
| Lead Designer | §4 flags design-system impact | N/A | — | — |

## 9. Post-implementation review

Filled in after the merge.

## 10. Related records

- Architecture/design references: [AI service §8](../../architecture/reports/ai_preread_service.md#8-in-the-app-hybrid-inference), [threat model](../../security/reports/firebase_and_ai_service_threat_model.md) (S-5, S-8, T-21 to T-23)
- Evaluation report(s): none
- Related Incident Report(s): none
- Related Problem record(s): none
