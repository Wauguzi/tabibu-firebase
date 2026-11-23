# UAT & Internal Testing Report — Tabibu

## Metadata

| Field | Value |
|---|---|
| Report ID | UAT-ITR-0001 |
| Title | The three roles end to end on the live project: booking to signed report and explanation, with the live pre-read and the outbreak alert loop |
| Date | 2026-11-23 (runs from 16 to 23 Nov) |
| Tester | Theo — CTO, Mobile Engineer; the Android run with the UI/UX designer |
| Build / commit | PR #17 merged (`3916705`), PR #18 merged (`5478275`), `fix/alert-engine-patches` at `4f4b5ef` |
| Environment | iPhone 14 (iOS); iOS Simulator for the 23 Nov Ebola loop; the Android APK on the designer's phone |
| Related CRQ | [CRQ-0003](../../crq/reports/CRQ-0003-gemini-thinking-level.md), [CRQ-0004](../../crq/reports/CRQ-0004-device-run-fixes.md), [CRQ-0005](../../crq/reports/CRQ-0005-ai-logic-templates-and-speech.md), [CRQ-0006](../../crq/reports/CRQ-0006-ui-ux-patches.md), [CRQ-0007](../../crq/reports/CRQ-0007-alert-engine-patches.md) |
| Overall status | ⚠️ PARTIAL: every flow the demo shows passes; six stories were not run and four passed in part (§4) |

## 1. Scope

**In scope:** what a patient, a doctor and a pathologist do from booking to result, against the
live project (`tabibu-86ea2`), its rules and its deployed functions, with every AI job live:

- the patient books by voice and by text, and reads and listens to the explanation once the doctor
  has discussed the result;
- the doctor orders for an app patient and a walk-in, attaches a pathologist, opens the signed
  report with its code, marks it discussed and approves the explanation;
- the pathologist accepts, records the sample, scores the live pre-read, asks the AI about one
  region, writes and signs, and starts consults;
- a signed notifiable finding (synthetic Ebola NAATs) becomes an event, a signal, a draft in
  English and Kiswahili, an approval, and a notice for the county's demo clinicians and
  patients.

**Out of scope:** the web build (§16 item 8 of the
[architecture](../../architecture/reports/mobile_architecture.md)); pushes on the iPhone, which its
free signing team cannot receive; real patients or real alerts (every alert in this project is
synthetic).

Each fix found on the way was made, tested and certified on the phone before its commit; the
CRQs above record them one by one. This report is the end state.

## 2. Test environment

| Item | Detail |
|---|---|
| Device / browser | iPhone 14 (iOS); iOS Simulator (23 Nov); an Android phone running the APK |
| Flutter version | Flutter 3.50.0, stable |
| Firebase project | `tabibu-86ea2` (live): functions in `europe-west1`, Gemini on the `global` endpoint |
| AI | `gemini-3.8-flash` in Cloud Functions and the two AI Logic templates; `gemini-3.8-flash-tts` for Listen; Apple Foundation Models and Gemini Nano on the phone, `gemini-3.5-flash-lite` as the cloud fallback |
| Accounts | The demo patient (Amina Otieno), doctor and approver (Dr. Achieng Odhiambo), pathologist (Dr. Wanjiru Kamau), and patients the doctor added (for example Zoe Jackson) |
| Locale / text scale / theme | `en` and `sw`; light; 1.0x on the devices (2.0x is held by the widget tests) |

## 3. User stories

The stories are the [template's](../templates/UAT_TESTING_TEMPLATE.md), with their IDs. Stories the
template does not have are added under **AI** and **CARE**.

### AI (added)

**US-AI-01 — Voice booking.** The patient speaks their symptoms; the transcript comes back to check
before sending.

**US-AI-02 — Ask AI on a region.** The pathologist frames a slide region and asks a question; the
answer is labelled as an AI draft and never saved.

**US-AI-03 — Listen.** The patient plays the approved explanation aloud, read verbatim in a voice
labelled as computer-generated.

**US-AI-04 — On the phone.** The patient tidies their typed symptoms, and the doctor summarises
their notes, on the phone's own model; the tidy falls back to the cloud where there is none.

**US-AI-05 — App Check.** The functions' logs show the app's App Check tokens verified.

### CARE (added)

**US-CARE-01 — Walk-in patient.** The doctor adds a patient, orders without a visit, marks the
result discussed in person and downloads the signed PDF.

**US-CARE-02 — Consult.** The pathologist opens a consult on a case, invites a doctor, who accepts
from the inbox.

**US-CARE-03 — Share code.** A report shared by code opens for its one recipient.

## 4. Pass / fail summary

| Story ID | Scenario | Result | Notes |
|---|---|---|---|
| US-AUTH-01 | Sign in per role | ✅ | Each demo account lands in its own shell. The web URL check is out of scope |
| US-AUTH-02 | Sign-out cache wipe | ✅ | One role after another on the same phone: none of the previous account's data shows |
| US-AUTH-03 | County choice | ⬜ Not run | Demo accounts read their county's notices (CRQ-0006 patch 32); changing the county and its topic was not tried |
| US-CASE-01 | Patient first | ✅ | Booked by voice and by text; the doctor reads the symptom summary in both languages |
| US-CASE-02 | Doctor first | ✅ | Walk-in patients added and ordered for (US-CARE-01) |
| US-CASE-03 | Order from catalogue | ⚠️ | Histopathology and NAATs for Ebola ordered from the one catalogue; a malaria smear order was not recorded |
| US-CASE-04 | Risk check advisory | ✅ | 23 Nov: "may fit a viral haemorrhagic fever. Follow Ministry of Health protocol", with "It never confirms or rules out a disease"; the protocol opens WHO's IDSR guidelines (CRQ-0007 entry 1) |
| US-PATH-01 | Draft waiting | ✅ | Time to report: the pre-read was Ready 2 min 43 s after acceptance (16 Nov, 45 tiles, confidence capped at Low); Ready again live on 19 Nov with new slides, after the tile-call fixes (CRQ-0006 patches 40, 42) |
| US-PATH-02 | Ranked worklist | ⚠️ | The desk and its filters certified (CRQ-0006 patch 41); the ranking order itself was not checked case by case |
| US-PATH-03 | Evidence links | ⬜ Not run | |
| US-PATH-04 | Relabel recalculates | ⬜ Not run | |
| US-PATH-05 | Sign | ✅ | Scored, edited, signed with a drawn signature; the doctor receives only the signed version, and "Compare with AI draft" shows the draft kept beside it |
| US-PATH-06 | Malaria profile | ⬜ Not run | The seeded malaria case carries a stored example; no live malaria pre-read was run |
| US-PATH-07 | Draft privacy | ⬜ Not run on the device | Held by the rules tests (S-1, S-2; 250 passing) |
| US-RES-01 | Doctor receives report | ✅ | Opened with its code from the inbox; downloads as a PDF named by its order |
| US-RES-02 | Cancer result gate | ✅ | The patient sees the result only after Mark as discussed |
| US-RES-03 | Plain-language explanation | ✅ | English and Kiswahili drafts approved by the doctor, then read by the patient (and US-AI-03) |
| US-ALR-01 | Baseline rule | ⬜ Not run live | The seeded malaria burst (`make seed-cases`) carries its draft; a live burst was not run |
| US-ALR-02 | Immediate rule | ✅ | One signed synthetic Ebola NAAT raised a signal on its own (19 and 23 Nov) |
| US-ALR-03 | Approval required | ✅ | Nothing delivered before approval; an edited approval kept the machine text beside it |
| US-ALR-04 | Two-phase delivery | ✅ | The county's demo clinicians, then its demo patients (19 Nov); the patient's notice shows the Demo pill and WHO's guidance (23 Nov) |
| US-ALR-05 | Event privacy | ✅ | The latest Ebola event holds `ageBand`, `alertRequested`, `category`, `countyId`, `createdAt`, `date`, `diseaseId`, `epiWeek`, `lastUpdatedAt`, `status`, `synthetic` and a random `uid`: no patient, case or facility field |
| US-NOT-01 | Inbox and badge | ⚠️ | Inbox and badge work; a read on one device clearing another was not tried |
| US-NOT-02 | Tap routing | ✅ | Inbox taps open the case, the consult, the conversation or the alert, and booking and consult requests are answered from the row (CRQ-0006 patches 43, 44); pushes on Android |
| US-AI-01 | Voice booking | ✅ | |
| US-AI-02 | Ask AI on a region | ✅ | CRQ-0006 patches 19, 20 |
| US-AI-03 | Listen | ✅ | Plays on iOS (CRQ-0006 patch 25) and is kept, encrypted, until sign-out (patch 36) |
| US-AI-04 | On the phone | ⚠️ | Run on the test phones. The iPhone 14 has no on-device model, so there the tidy used its cloud fallback and the notes summary stays hidden; a run on an Apple Intelligence phone is still to do ([CRQ-0002](../../crq/reports/CRQ-0002-hybrid-inference-bridge.md) §7) |
| US-AI-05 | App Check | ✅ | Verified in the function logs; still not enforced (architecture §16 item 7) |
| US-CARE-01 | Walk-in patient | ✅ | CRQ-0006 patches 37, 38 |
| US-CARE-02 | Consult | ✅ | One open consult per case; the invitation names the inviter (CRQ-0006 patch 39) |
| US-CARE-03 | Share code | ✅ | Returns to the report with "Shared with {name}" (CRQ-0006 patch 45) |

## 5. Known issues (non-blocking)

| ID | Description | Feature | Severity | Linked record |
|---|---|---|---|---|
| KI-1 | The iPhone build receives no pushes: its free signing team cannot add the push entitlement. The inbox carries every notice | Notifications | Low | [CRQ-0006 §3](../../crq/reports/CRQ-0006-ui-ux-patches.md#3-scope) |
| KI-2 | Uploading slides takes about 30 seconds | Slides | Low | Deferred to the design pass |
| KI-3 | App Check is active but not enforced | Security | Medium | [Architecture §16 item 7](../../architecture/reports/mobile_architecture.md#16-known-architectural-debt--watchlist) |
| KI-4 | A demo alert delivered before 23 Nov keeps "Demo:" in its stored text; new alerts do not | Alerts | Low | [CRQ-0007 entry 6](../../crq/reports/CRQ-0007-alert-engine-patches.md) |

## 6. Regression check

| Feature | Spot-checked | Verdict |
|---|---|---|
| The automated suites on the final tree | `make test` 3,963; `make functions-test` 703; `make rules-test` 250; analyze, `bloc_lint`, format and spelling clean | ✅ |
| Rules in force | The live Firestore and Storage rules match the repository (Firestore differs by a comment only) | ✅ |

## 7. Sign-off

| Role | Required when | Name | Date | Decision |
|---|---|---|---|---|
| CTO / Mobile Engineer | Always | Theo | 2026-11-23 | ✅ Approved |
| Clinical Reviewer | Any story under PATHOLOGIST, RESULTS or ALERTS is in scope | Covered by CTO | 2026-11-23 | ✅ Approved |
| Security Analyst | Rules or auth stories in scope | Covered by CTO | 2026-11-23 | ✅ Approved |

## 8. Related records

- CRQ: [CRQ-0003](../../crq/reports/CRQ-0003-gemini-thinking-level.md) to
  [CRQ-0007](../../crq/reports/CRQ-0007-alert-engine-patches.md)
- Evaluation report: [EVAL-0001](./EVAL-0001-cancer-preread-gemini-baseline.md) (the pre-read's
  held-out numbers; no model, prompt or label changed in this cycle)
- IRP: none
