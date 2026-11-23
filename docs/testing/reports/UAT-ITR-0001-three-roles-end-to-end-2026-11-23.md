# UAT & Internal Testing Report — Tabibu

## Metadata

| Field | Value |
|---|---|
| Report ID | UAT-ITR-0001 |
| Title | The three roles end to end on the live project: booking to a signed, explained result, with the live pre-read and the outbreak alert loop |
| Date | 2026-11-23 (runs from 16 to 23 Nov) |
| Tester | Theo — CTO, Mobile Engineer; the Android run with the UI/UX designer |
| Build / commit | PR #17 merged (`3916705`), PR #18 merged (`5478275`), `fix/alert-engine-patches` at `4f4b5ef` |
| Environment | iPhone 14 (iOS); the iOS Simulator (iPhone 18 Pro); the Android APK on a phone |
| Related CRQ | [CRQ-0003](../../crq/reports/CRQ-0003-gemini-thinking-level.md), [CRQ-0004](../../crq/reports/CRQ-0004-device-run-fixes.md), [CRQ-0005](../../crq/reports/CRQ-0005-ai-logic-templates-and-speech.md), [CRQ-0006](../../crq/reports/CRQ-0006-ui-ux-patches.md), [CRQ-0007](../../crq/reports/CRQ-0007-alert-engine-patches.md) |
| Overall status | ✅ PASS |

## 1. Scope

A patient, a doctor and a pathologist, from booking to result, on the live project
(`tabibu-86ea2`) with its deployed rules and functions and every AI job live:

- the **patient** books by voice or by text, then reads and listens to their result's explanation
  once their doctor has discussed it;
- the **doctor** orders for an app patient or a walk-in, sends the order to a pathologist, opens
  the signed report, marks it discussed and approves the explanation;
- the **pathologist** accepts the case, records the sample, scores the live pre-read, asks the AI
  about one region, writes and signs the report, and opens consults;
- a signed **notifiable finding** (synthetic Ebola NAATs) becomes an anonymous event, an alert
  draft in English and Kiswahili, an approval, and a notice for the county's clinicians and
  patients.

Every fix found on the way was made, tested and certified on the phone before its commit; the
CRQs above record each one. This report is the end state.

## 2. Test environment

| Item | Detail |
|---|---|
| Device / browser | iPhone 14 (iOS); the iOS Simulator (iPhone 18 Pro); an Android phone running the APK |
| Flutter version | Flutter 3.50.0, stable |
| Firebase project | `tabibu-86ea2` (live): functions in `europe-west1`, Gemini on the `global` endpoint |
| AI | `gemini-3.8-flash` in Cloud Functions and the two AI Logic templates; `gemini-3.8-flash-tts` for Listen; `gemini-3.5-flash-lite` for the symptom tidy in the cloud |
| Accounts | The demo patient (Amina Otieno), doctor and alert approver (Dr. Achieng Odhiambo) and pathologist (Dr. Wanjiru Kamau), and patients the doctor added (for example Zoe Jackson) |
| Locale / text scale / theme | `en` and `sw`; light; the widget tests hold 2.0x text |

## 3. User stories

### Patient

**US-AUTH-01 — I sign in to my own space.** Each demo account opens its own role's home.

**US-AI-01 — I say what is wrong.** I speak my symptoms when booking, and check the words
before sending.

**US-AI-04 — I tidy what I typed.** I ask for a cleaner version of my symptom note and keep it
only if I choose "Use this".

**US-CASE-01 — I book a doctor.** I book by voice or by text, and my doctor reads a summary of
my symptoms in English and Kiswahili.

**US-RES-02 — I see my result only after we talk.** The result stays hidden until my doctor marks
it discussed.

**US-RES-03 — I read my result in plain words.** The explanation my doctor approved is there in
English and in Kiswahili.

**US-AI-03 — I listen to it.** I play the approved explanation aloud, read word for word in a
voice marked as computer-generated.

### Doctor

**US-CASE-02 — I care for a walk-in.** I add a patient in front of me and order for them
without a booking.

**US-CASE-03 — I order from one catalogue.** I order a histopathology examination or NAATs for
Ebola, with the specimen and payment, and send it to a pathologist.

**US-CASE-04 — The risk check advises me.** For notes that fit a viral haemorrhagic fever, the AI
points me to the protocol, says it never confirms or rules out a disease, and the protocol opens
WHO's IDSR guidelines.

**US-RES-01 — I receive the signed report.** I open it with the code from my inbox and download it
as a PDF named by its order.

**US-CARE-01 — I discuss it in person.** I mark a walk-in's result discussed in person.

**US-ALR-03 — I approve the alert.** The draft waits for me with its facts filled in, in English
and Kiswahili; nothing goes out until I approve, and an edit is kept beside the draft.

### Pathologist

**US-PATH-01 — The pre-read is waiting.** When I accept a case, the AI's pre-read is ready within
minutes, labelled as AI, with its confidence shown.

**US-PATH-02 — I work from my desk.** My desk lists my cases, with filters.

**US-AI-02 — I ask the AI about a region.** I frame part of a slide and ask a question; the
answer is labelled as an AI draft and never saved.

**US-PATH-05 — I sign the report.** I score the pre-read, write the report and sign it; the doctor
receives only the signed version, and the AI draft is kept beside it.

**US-CARE-02 — I open a consult.** I start a consult on a case and invite a doctor, who accepts
from their inbox.

**US-CARE-03 — I share a report.** A report shared by code opens for its one recipient.

### The county alert

**US-ALR-02 — One confirmed case raises a signal.** Signing one confirmed Ebola NAAT with a
notifiable finding raises a signal on its own.

**US-ALR-04 — Clinicians first, then patients.** Once approved, the alert reaches the county's
clinicians and then its patients, as a notice marked Demo, with WHO's guidance.

**US-ALR-05 — Nobody is named.** The event behind the alert holds only the disease, the county,
the date, the epi-week and an age band.

### Everyone

**US-AUTH-02 — Signing out leaves nothing behind.** After one account signs out, the next account
on the same phone sees none of its data.

**US-NOT-01 — My inbox keeps count.** New notices appear in my inbox with an unread badge.

**US-NOT-02 — A notice takes me there.** Tapping a notice opens its case, consult, conversation or
alert, and a booking or consult request is answered from the notice itself.

**US-AI-05 — The app proves it is the app.** The functions verify the app's App Check tokens.

## 4. Pass / fail summary

| Story ID | Scenario | Result | Notes |
|---|---|---|---|
| US-AUTH-01 | Sign in to my own space | ✅ | All three demo accounts |
| US-AI-01 | Voice booking | ✅ | |
| US-AI-04 | Symptom tidy | ✅ | The iOS Simulator (iPhone 18 Pro) |
| US-CASE-01 | Book a doctor | ✅ | |
| US-RES-02 | Result only after the talk | ✅ | |
| US-RES-03 | Plain-language explanation | ✅ | English and Kiswahili |
| US-AI-03 | Listen | ✅ | Kept on the phone, encrypted, until sign-out (CRQ-0006 patch 36) |
| US-CASE-02 | Walk-in patient | ✅ | CRQ-0006 patch 37 |
| US-CASE-03 | Order from one catalogue | ✅ | |
| US-CASE-04 | Risk check advisory | ✅ | 23 Nov (CRQ-0007 entry 1) |
| US-RES-01 | Signed report | ✅ | CRQ-0006 patch 38 |
| US-CARE-01 | Discussed in person | ✅ | |
| US-ALR-03 | Approve the alert | ✅ | 19 and 23 Nov (CRQ-0007 entries 3, 8) |
| US-PATH-01 | Pre-read waiting | ✅ | Time to report: Ready 2 min 43 s after acceptance (16 Nov, 45 tiles); Ready live again on 19 Nov |
| US-PATH-02 | The desk | ✅ | CRQ-0006 patch 41 |
| US-AI-02 | Ask AI on a region | ✅ | CRQ-0006 patches 19, 20 |
| US-PATH-05 | Sign | ✅ | |
| US-CARE-02 | Consult | ✅ | CRQ-0006 patch 39 |
| US-CARE-03 | Share code | ✅ | CRQ-0006 patch 45 |
| US-ALR-02 | One case raises a signal | ✅ | 19 and 23 Nov |
| US-ALR-04 | Clinicians, then patients | ✅ | 19 Nov; the notice's Demo pill and WHO guidance on 23 Nov |
| US-ALR-05 | Nobody is named | ✅ | The latest Ebola event's fields: `ageBand`, `alertRequested`, `category`, `countyId`, `createdAt`, `date`, `diseaseId`, `epiWeek`, `lastUpdatedAt`, `status`, `synthetic` and a random `uid` |
| US-AUTH-02 | Sign-out leaves nothing | ✅ | |
| US-NOT-01 | Inbox and badge | ✅ | |
| US-NOT-02 | A notice takes me there | ✅ | CRQ-0006 patches 43, 44 |
| US-AI-05 | App Check | ✅ | Verified in the function logs |

## 5. Regression check

| Feature | Spot-checked | Verdict |
|---|---|---|
| The automated suites on the final tree | `make test` 3,963; `make functions-test` 703; `make rules-test` 250; analyze, `bloc_lint`, format and spelling clean | ✅ |
| Rules in force | The live Firestore and Storage rules match the repository | ✅ |

## 6. Sign-off

| Role | Required when | Name | Date | Decision |
|---|---|---|---|---|
| CTO / Mobile Engineer | Always | Theo | 2026-11-23 | ✅ Approved |
| Clinical Reviewer | Any story under PATHOLOGIST, RESULTS or ALERTS is in scope | Covered by CTO | 2026-11-23 | ✅ Approved |
| Security Analyst | Rules or auth stories in scope | Covered by CTO | 2026-11-23 | ✅ Approved |

## 7. Related records

- CRQ: [CRQ-0003](../../crq/reports/CRQ-0003-gemini-thinking-level.md) to
  [CRQ-0007](../../crq/reports/CRQ-0007-alert-engine-patches.md)
- Evaluation report: [EVAL-0001](./EVAL-0001-cancer-preread-gemini-baseline.md), the pre-read's
  held-out numbers
