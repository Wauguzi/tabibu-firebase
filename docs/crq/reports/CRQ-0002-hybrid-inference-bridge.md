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
| Commit(s) / PR | [PR #14](https://github.com/Wauguzi/tabibu-firebase/pull/14), merged to `main` as `3e0458e` on 2026-11-16 (33 commits from `feat/hybrid-bridge`) |

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
| Localisation (en, sw) | Added | Nine `hybrid*` strings in both ARB files. Both actions hide in Kiswahili, so the Kiswahili copy is kept for parity and not shown |
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
7. The pull request, then the device runs: the pull request merged first so CI could build and distribute a signed APK for them.

## 7. Testing & verification evidence

| Check | Result |
|---|---|
| `make analyze` / `make bloc-lint` | Pass — no issues |
| `make test` (`TZ=UTC`) | Pass — 3,554 tests, including the stripping, Remote Config, retry, analytics, lifecycle and 2.0x tests; also run between 21:00 and 24:00 UTC, when Nairobi's date differs |
| `make spell` / `make release-check` | Pass — 1,068 files; the version follows the convention |
| iOS RunnerTests (simulator) | Pass — 6: source and status mapping, the routing matrix, the prompts, a status call with a model option, a network error; run on one named simulator |
| iOS simulator build | Pass |
| Android plugin | Pass — compiles; 5 JVM contract tests (routing, cut-off, failure codes, the model option); a signed release APK builds locally and in CI on the upgraded toolchain |
| CI on the merged head (`fc5f445`) | Pass — `functions`, `test` and `build` side by side, then `distribute`, in 28 minutes; the build reached App Distribution and its Dart symbols Crashlytics |
| Manual run | The symptom tidy passes on the iOS Simulator (iPhone 18 Pro; [UAT-ITR-0001](../../testing/reports/UAT-ITR-0001-three-roles-end-to-end-2026-11-23.md) US-AI-04). The notes summary follows the guardrail change in CRQ-0007 entry 11; the airplane-mode run on an Apple Intelligence device is still to do |
| Certification | Pending |

## 8. Approval

| Role | Required when | Name | Date | Decision |
|---|---|---|---|---|
| Author | Always | Theo | 2026-11-15 | — |
| Engineering reviewer | Always, on the pull request | Greptile | 2026-11-16 | Approved: 5/5 after one round, held on the final head |
| Clinical Reviewer | §4 flags clinical-safety impact or changes clinical wording | Covered by CTO | 2026-11-15 | Approved: AI-labelled, applied only on the person's tap, never stored |
| Security Analyst | §4 flags security impact | Covered by CTO | 2026-11-16 | Approved: T-21 in place (App Check enforced on AI Logic, authenticated users only, 20 a minute per user, a $20 spend cap); T-23 waits until AI monitoring is turned on |
| Compliance Officer | §4 flags data protection impact | Covered by CTO | 2026-11-15 | Approved: the S-8 exception, with contact details stripped |
| Lead Designer | §4 flags design-system impact | N/A | — | — |

## 9. Post-implementation review

**Pre-review pass (15 Nov), before the pull request.** Eight findings, all
fixed on this branch, each new guard proven by breaking it and watching its
test fail:

1. Remote Config never reached the actions: the switches and the cloud
   model could not change anything, so the rollback in §5 did not work. The
   lookup now registers as `HybridConfigLookup` and the widget resolves its
   settings from it.
2. A failed run hid the action, leaving no way to retry without editing.
3. A failed run, "Use this" and "Done" logged nothing; every outcome now
   logs one event (`hybrid_inference` with an outcome, `hybrid_proposal`).
4. The bloc's analytics hook bypassed the `getIt` fallback convention.
5. The widget ignored a new controller and a locale change after its first
   frame.
6. `download()`'s comment claimed a native download on Wi-Fi that neither
   plugin makes.
7. The review rules' S-8 still described server-side speech, and S-8 did not
   name the notes summary's reader; both now match the threat model.
8. No 2.0x text test; one now runs in English and Kiswahili.

**Greptile round 1 (15 Nov) on PR #14.** Five P2 findings, fixed on this branch
(`16663c2`, `ebc6532`, `7ccd221`, `bd2d803`, `a7f1b50`):

1. The web tidy always failed: a missing plugin read as "no model". `status()`
   now returns `unsupported` on `MissingPluginException`, hiding both actions.
2. Android checked STABLE while generating with the configured option. Status,
   download and warm-up now take `modelOption` and build the model per option.
3. Moving the cursor discarded a proposal: `_onContext` now returns early when
   text, locale and `online` are unchanged.
4. Status read once per screen: the widget re-reads it on foreground resume via
   `HybridAssistStatusRefreshed`, settling unless running or proposed.
5. Docs named a sanitiser class that does not exist, and the model path skipped
   sanitising: `HybridRequest.toMap()` now runs `sanitizePaste` on every input
   (then strips contact details from a tidy), the architecture and review rules
   name `sanitizePaste`, and both bio fields sanitise a paste.

Greptile scored 4/5 on the first review and 5/5 once these were fixed; the
score held through the CI fixes below.

**CI on the pull request (15–16 Nov).** The first runs to reach the signed
release build failed in four ways, none of them in the hybrid code:

1. The home header dated itself by the device's clock while its test used
   Nairobi's, so the test failed between 21:00 and 24:00 UTC. The header now
   uses `nairobiNow()`, like the doctor's home (`84aee73`).
2. The first signed build was cancelled at the job's 45-minute limit, with
   every check passed and the APK nearly built (`e42692a`, `2a38868`).
3. AGP 9.3.1's release lint calls a Java 21 method, so it failed on CI's
   JDK 17. CI now runs Gradle on JDK 21; the code still targets Java 17
   (`5148b97`). The debug builds used to prove the upgrade never run that
   lint.
4. The runner then stopped responding mid-build. A private repository's
   runner has 2 CPUs and 8 GB, so the tests and the signed build now run as
   separate jobs, Gradle runs one worker, and testers get the build only when
   both pass (`c56a288`).

**Still to record:** the device runs in §7, which set the implementation
date.

## 10. Related records

- Architecture/design references: [AI service §8](../../architecture/reports/ai_preread_service.md#8-in-the-app-hybrid-inference), [threat model](../../security/reports/firebase_and_ai_service_threat_model.md) (S-5, S-8, T-21 to T-23)
- Evaluation report(s): none
- Related Incident Report(s): none
- Related Problem record(s): none
