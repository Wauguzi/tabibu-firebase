# Change Request (CRQ) — Tabibu

| Field | Value |
|---|---|
| CRQ number | CRQ-0004 |
| Title | Fixes from the first device run: the risk check, pre-read timing, audio controls and App Check on iOS |
| Requested by | Theo — CTO |
| Date raised | 2026-11-16 |
| Date implemented | 2026-11-16 |
| Priority | P2 High — see [`mobile_workflow.md` §7](../../workflow/reports/mobile_workflow.md#7-escalation--severity) |
| Change type | Normal |
| Commit(s) / PR | [PR #17](https://github.com/Wauguzi/tabibu-firebase/pull/17), merged to `main` as `3916705` on 2026-11-16; the fixes are `1a3b5e2` (risk check), `e351d51` (notification time), `ce14c7c` and `eb896ae` (audio), `b81aa21` (App Check), `eb09218` (Delete account) and `1f51447` (the pre-read wait) |

## 1. Description of change

The first run on an iPhone 14 with the seeded accounts (16 Nov) found six
defects. Each is fixed here.

1. **The risk check always failed.** Its response schema listed an empty
   string among the input languages, and `gemini-3.8-flash` refuses an empty
   enum value with `INVALID_ARGUMENT`, so every risk check and notes
   translation ended as `ServiceError` and the doctor read "The risk check
   didn't run. Order as usual." The schema now names `en`, `sw` and `mixed`;
   "no notes" is set in code after the call. Deployed 16 Nov.
2. **"Pre-read ready" was dated when the run started.** The trigger read the
   clock before processing the run, so a three-minute run's notification was
   three minutes old on arrival, and the app's two-minute window for a banner
   never showed it. The time is read after the run. Deployed 16 Nov.
3. **"Sample received" opened onto a refusal.** While the pre-read runs, the
   server refuses to start the report (`prereadPending`), and the pathologist
   met a failure screen. The button now reads "Awaiting pre-read" and is
   disabled, under a notice that it takes about three minutes; the
   pre-read's inbox row reopens the workspace, so the button turns on by
   itself, and "Check again" reads the case from the server. A case queued
   for more than 30 minutes, the server's own stale window, is offered as
   usual, so a lost run cannot strand it, and a refusal now names the
   pre-read (`prereadPending`) instead of a generic error. The doctor's note
   on ordering now says when the pre-read starts and how long it takes.
4. **Pause did nothing during a voice note's first playback, and the MDT
   preview's icon lagged.** The player awaited `just_audio`'s `play()`,
   which completes only when playback pauses or ends. It now returns once
   playback starts and reports the end on its stream; the composer's preview
   follows that stream, and the listen card shows play, pause, or the
   in-progress mark while loading.
5. **iOS App Check used DeviceCheck in debug builds.** `firebase_core`
   registers before `firebase_app_check` and configures Firebase at once
   (`GoogleService-Info.plist` is in the bundle), so App Check read its
   provider factory before the plugin installed one and fell back to
   DeviceCheck, which this app does not register. The App Check plugin now
   registers first in `AppDelegate`, so the debug token and App Attest work
   as `bootstrap` asks.
6. **"Delete account" was offered with nothing behind it.** The row had no
   action, and the seeded demo accounts are shared, so none should be offered
   for deletion. It is commented out until a real deletion flow exists.

## 2. Business justification

These are the defects a judge would meet first: no risk check, a
pathologist told to wait without being told why, audio controls that do not
pause, and an iPhone whose cloud features App Check refuses.

## 3. Scope

**In scope:** the six fixes, their tests and the docs that described them.

**Explicitly out of scope:**

- **A chat opened before a booking is accepted** still shows a generic error.
  It is queued with its fix (`.briefs`), P3.
- **App Attest in release builds:** the signing team is a free Personal
  Team, which cannot add the entitlement. Judges install the Android APK.
- **Six event triggers still carry a secret binding from an earlier model
  provider:** no code reads it, and the CLI keeps a binding it did not
  create. The bindings go after submission.

## 4. Impact assessment

| Area | Impact | Notes |
|---|---|---|
| Data model (Firestore, Hive) | None | |
| Roles & case scoping | None | |
| Clinical safety | None | The pre-read still waits for the pathologist; no gate changes |
| AI service (prompts, models, thresholds) | Changed | The risk check's response schema; no prompt or model change |
| Security (rules, App Check, RASP, secrets) | Affected | App Check on iOS now uses the provider `bootstrap` names |
| Data protection (PHI, de-identification, model endpoints) | None | |
| Design system / UI consistency | Existing pattern | `NoticeCard`, `TabibuButton`, the existing play and pause icons |
| Localisation (en, sw) | Added | Four `workspaceAwaitingPreread*` strings and `errorPrereadPending`; `orderPathologistAiNote` reworded |
| Existing data | None | |

## 5. Risk & rollback plan

**Risk level:** Low. Each fix is small and tested.

**Rollback plan:** revert the commits; the two server fixes need a functions
deploy to roll back, which restores the defects they fixed.

## 6. Implementation plan

1. Reproduce each defect from the device logs or a live call.
2. Fix it with a test that fails before the fix.
3. Deploy the two server fixes the same day.
4. Run the device again on this branch.

## 7. Testing & verification evidence

| Check | Result |
|---|---|
| `make analyze` / `make bloc-lint` | Pass — no issues |
| `make test` (`TZ=UTC`) | Pass — 3,673 on the merged branch |
| `make functions-test` | Pass — 660, including the empty-enum guard and the notification time |
| Red proofs | Each new guard fails with its fix removed |
| Live calls | The risk check with and without notes returns `inputLanguage` `en` and `''` |
| iOS simulator build | Pass, with the App Check registration order |
| Manual run | Pass — the iPhone 14 through CRQ-0006's device run (17–23 Nov), App Check tokens verified in the function logs ([UAT-ITR-0001](../../testing/reports/UAT-ITR-0001-three-roles-end-to-end-2026-11-23.md)) |
| Certification | 2026-11-23, Theo |

## 8. Approval

| Role | Required when | Name | Date | Decision |
|---|---|---|---|---|
| Author | Always | Theo | 2026-11-16 | — |
| Engineering reviewer | Always, on the pull request | Greptile — [PR #17](https://github.com/Wauguzi/tabibu-firebase/pull/17) | 2026-11-16 | 5/5 — Approved after one round |
| Clinical Reviewer | §4 flags clinical-safety impact or changes clinical wording | Covered by CTO | 2026-11-16 | Approved: the pre-read wording now matches what happens |
| Security Analyst | §4 flags security impact | Covered by CTO | 2026-11-16 | Approved: App Check uses the intended provider |
| Compliance Officer | §4 flags data protection impact | N/A | — | — |
| Lead Designer | §4 flags design-system impact | N/A | — | — |

## 9. Post-implementation review

**Pre-review pass (16 Nov), before the pull request.** A local Greptile-style
pass found the awaiting state could strand a case: a pre-read lost after
queueing kept the button off for good, and a case opened from the cache
never learned the pre-read had landed. The wait now ends at the server's
30-minute stale window, opening a queued case reads the server, "Check
again" asks for the case, and an inbox row already present when the case
loads reopens it. Each has a test that fails without it.

The same pass tightened the audio fixes of §1.4: the recording cue waits for
its beep to end before the microphone opens, a clip that fails to play says
so instead of sitting on pause, a voice note retried after a failure
reloads, MDT playback is counted as MDT, and signing out stops any clip, so
a narrated result does not play on for the next person to use the phone. It
also corrected the docs that described the in-app AI paths.

The device run follows.

## 10. Related records

- Architecture/design references: [AI service §2](../../architecture/reports/ai_preread_service.md#2-invocation), [architecture](../../architecture/reports/mobile_architecture.md)
- Evaluation report(s): none
- Related Incident Report(s): none; no patient was affected
- Related Problem record(s): none
