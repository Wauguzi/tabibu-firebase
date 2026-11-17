# Change Request (CRQ) — Tabibu

| Field | Value |
|---|---|
| CRQ number | CRQ-0006 |
| Title | UI and UX patches from the end-to-end device run |
| Requested by | Theo — CTO |
| Date raised | 2026-11-17 |
| Date implemented | Pending; patches land as the run finds them |
| Priority | P3 Medium — see [`mobile_workflow.md` §7](../../workflow/reports/mobile_workflow.md#7-escalation--severity) |
| Change type | Normal |
| Commit(s) / PR | `fix/ui-ux-patches`; the pull request follows the run |

## 1. Description of change

The end-to-end run on an iPhone 14 with the merged build of PR #17 (17 Nov), as a patient, a
doctor and a pathologist, finds small defects in what a person sees. Each is fixed on this
branch as it is found, certified on the phone, then recorded here.

1. **The appointment chat opened onto a refusal before the doctor accepted.** The patient's
   "Appointment chat" row was tappable on a *Requested* booking. The server opens a chat only
   for an accepted or completed visit (`conversationUnavailable`), and the app had no message
   for that refusal, so the patient read "Something went wrong" with a Retry that could not
   work. The row is now disabled while the booking is requested, with "Opens once {doctor}
   accepts" under it, turns on by itself when the doctor accepts, and is absent on a declined,
   cancelled, expired or missed booking. The chat screen, if reached early another way, says
   "Chat opens once your doctor accepts the appointment" and offers Back. The doctor's side
   needed no change: its chat entry appears only for an accepted visit. Certified on the
   iPhone, 17 Nov.
2. **The Results filters took two lines.** "All", "With your doctor" and "Shared" sat in a
   wrap that broke onto a second line in Swahili and at larger text, pushing the list down.
   They now sit on one line that scrolls sideways, as Find a doctor's specialty filters do.
   Certified on the iPhone, 17 Nov.

## 2. Business justification

These are the rough edges a judge meets in the first minutes as each role. A message that
says why something is unavailable, and when it will be, replaces a generic failure.

## 3. Scope

**In scope:** the patches listed in §1, their tests and the strings they add.

**Explicitly out of scope:**

- **Push on the iPhone:** the free Personal Team cannot add the push entitlement, so APNs
  issues no token; the in-app inbox still works and Android receives pushes (CRQ-0004 §3).
- **Server rules:** no Firestore or Functions rule changes; the app explains the server's
  existing refusals.

## 4. Impact assessment

| Area | Impact | Notes |
|---|---|---|
| Data model (Firestore, Hive) | None | |
| Roles & case scoping | None | The server's chat rule is unchanged |
| Clinical safety | None | No AI output, result or alert path changes |
| AI service (prompts, models, thresholds) | None | |
| Security (rules, App Check, RASP, secrets) | None | |
| Data protection (PHI, de-identification, model endpoints) | None | |
| Design system / UI consistency | Extended | `GroupedRow` gains a caption and a disabled state: muted text, the neutral icon tone, no chevron, announced as a disabled button with its reason |
| Localisation (en, sw) | Added | `chatRowWaitingCaption`, `errorConversationUnavailable` |
| Existing data | None | |

## 5. Risk & rollback plan

**Risk level:** Low. Each patch is small, app-side and tested.

**Rollback plan:** revert the patch's commit; no deploy or data change is involved.

## 6. Implementation plan

1. Run the app end to end on the phone, as each role.
2. For each defect: fix it with a test that fails without the fix, run the full gates, then
   Theo hot-restarts and certifies on the phone before the commit.
3. One pull request for the branch once the run ends, reviewed to 5/5.

## 7. Testing & verification evidence

| Check | Result |
|---|---|
| `make analyze` / `make bloc-lint` | Pass — no issues |
| `make test` (`TZ=UTC`) | Pass — 3,686 after patch 2 |
| `make spell` | Pass — 0 issues |
| Red proofs | Patch 1: the disabled row, the requested state and Back instead of Retry each fail with the fix removed. Patch 2: the one-line test fails against the old wrap |
| Manual run | Patches 1 and 2 certified on the iPhone 14, 17 Nov; the run continues |
| Certification | Pending the end of the run |

## 8. Approval

| Role | Required when | Name | Date | Decision |
|---|---|---|---|---|
| Author | Always | Theo | 2026-11-17 | — |
| Engineering reviewer | Always, on the pull request | Greptile — pending | — | — |
| Clinical Reviewer | §4 flags clinical-safety impact or changes clinical wording | N/A | — | — |
| Security Analyst | §4 flags security impact | N/A | — | — |
| Compliance Officer | §4 flags data protection impact | N/A | — | — |
| Lead Designer | §4 flags design-system impact | Covered by CTO | 2026-11-17 | Approved: the disabled row follows the disabled button's muted colour |

## 9. Post-implementation review

Filled in after the run.

## 10. Related records

- Architecture/design references: [design system](../../design/reports/mobile_design_system.md), [CRQ-0004](./CRQ-0004-device-run-fixes.md), [CRQ-0005](./CRQ-0005-ai-logic-templates-and-speech.md)
- Evaluation report(s): none
- Related Incident Report(s): none
- Related Problem record(s): none
