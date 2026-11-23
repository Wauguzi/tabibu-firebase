# Change Request (CRQ) — Tabibu

| Field | Value |
|---|---|
| CRQ number | CRQ-0007 |
| Title | Alert engine patches from the Ebola device run: sources, drafts filled in, the demo marker |
| Requested by | Theo — CTO |
| Date raised | 2026-11-23 |
| Date implemented | Pending; patches land as they are certified |
| Priority | P2 High — see [`mobile_workflow.md` §7](../../workflow/reports/mobile_workflow.md#7-escalation--severity) |
| Change type | Normal |
| Commit(s) / PR | `fix/alert-engine-patches`; the pull request follows |

## 1. Description of change

The Ebola loop on the iPhone 14 (23 Nov): a doctor orders NAATs for Ebola, the pathologist signs a
positive critical finding, the alert is drafted, approved and delivered to the county's demo
accounts. It works end to end; these patches fix what the doctor, the approver and the patient
read on the way. Each entry is filled in as its patch lands.

1. **The order's Ministry of Health protocol link would not load.** The IDSR handbook's host
   answered in 8 to 22 s and timed out one try in three (23 Nov), which a phone shows as a broken
   page. Each disease's case definition now cites the WHO AFRO IDSR Technical Guidelines, 3rd
   edition (its publication page loads in under a second), each checked against Booklet Two's
   standard case definitions: six were older Kenyan wordings and now follow WHO (cholera from age
   2, plague with its exposure, meningitis without "altered consciousness", yellow fever's
   epidemiological link as probable, anthrax's two supportive tests, the new influenza subtype).
   The statutory reminder (forms MOH 502 and 505) is Kenyan, so it keeps the handbook, linked at
   its archived copy (the same PDF, 3 to 6 s).
2. **"Order a test" stayed beside "End appointment" after the order went to a pathologist.**
   It read as if nothing had been ordered while the pathologist's answer was awaited. Once this
   visit's order is sent and not cancelled, End appointment is the bar's only button, full width,
   in its own style. Unsent or refused still offers Attach pathologist; no order, a cancelled one
   or an earlier visit's case still offers Order a test.
3. **The approver had to replace `{disease}` and the other placeholders by hand, and a long box
   marked the demo.** The model writes placeholders by design and never sees case data; code
   filled them only at delivery. The review screen and the edit sheet now fill the same values
   (the disease in each language, the county, the count, the week) from the alert's own fields,
   so the approver reads "Ebola virus disease in Nairobi County" and types nothing. Approving
   unchanged still sends the machine text, so it stays an approval as is; an edited segment is
   sent as typed, and a changed evidence revision is still refused. The demo box became the pill
   of entry 4.
4. **The patient read "Demo: Demo: …", a county chip the title repeats, and guidance credited to a
   press release about Ituri Province in the DRC.** A notice's footer and "Read the guidance" use
   its first patient source. Patient guidance now cites only a standing WHO or MoH source, each
   line checked against it: Ebola's WHO fact sheet replaces the Ituri release (the travel and
   soap clauses went, since the sheet does not give them); Rift Valley fever, dengue, malaria and
   measles move off a 2023 heavy-rains release; cholera's lines, held back as OCR, now ship from
   WHO's fact sheet; anthrax's newspaper-sourced lines are removed, as no standing source exists
   online. A test refuses a press release, statement, advisory or non-WHO, non-MoH publisher.
   "Demo: Demo:" was the template's own prefix plus the screen's. The template no longer prefixes
   anything; a synthetic alert carries a "Demo" pill instead (the timeline's Now tone) on the
   review, sent and notice screens, and its pushes keep "Demo:" since a lock screen has no pill.
   The "Health notice · {county}" chip above the title is gone: the title names the county.
5. **Reopening a report blanked the explanation drafts and fetched them again.** The reader's
   quick first paint replaced the state with no drafts, so the doctor saw "Waiting for the AI
   draft" until both were read from Firestore once more. The drafts read in this session now
   survive the reopen, a Ready one is not fetched again, and an approval found on the server
   replaces its draft. They stay in memory only: unapproved model text is still never written to
   the phone (Theo, 23 Nov, keeping the architecture's rule).
6. **This week's Ebola alert still read "Demo: …"** because it was drafted before the deploy and
   only its count changed after. `functions/scripts/redraft-alert.ts` asks for a new draft as the
   approver would, through the same handler (dry run by default); run once on 23 Nov, the alert
   came back drafted by the current template.
7. **The Kiswahili draft card named its readers in English.** Each card's audience lines now come
   from the card's own language ("Kwa madaktari wa Nairobi na karibu"), on the review card, the
   edit sheet and the sent screen; the language heading and the AI label stay in the app's
   language, since they speak to the approver.
8. **An approver could not ask for a new draft from the phone,** though the server offers it.
   The review screen's More menu now starts with "Ask for a new draft" (up to 3 per alert); the
   screen follows the alert until the new draft is in (every 3 s, up to 90 s), and the two
   refusals, the limit and an alert past drafting, each say so and keep the current draft.
9. **No report showed how the app was tested end to end.** UAT-ITR-0001 records the three roles
   against the live project from 16 to 23 Nov, story by story, and the README's Trying it points
   to it. CRQ-0002, -0004 and -0005 take their device runs from
   it.
10. **The docs described a backend that was not yet live.** The threat model's controls now read
    live (the deployed rules match the repository); the architecture, AI service, notifications
    and alert engine reports give the current status, the pre-read's tile limits and the twelve
    switches; CRQ-0006 drops a wrong cross-reference.
11. **The doctor's notes summary on Apple's on-device model.** Both on-device tasks only rewrite
    text the person typed, so the model now runs with Apple's guardrails for content
    transformations (`permissiveContentTransformations`), which are meant for that, instead of
    the defaults, which turn away ordinary clinical wording. The notes still never leave the
    phone. A failed call now logs which kind of error it was, never the text.

## 2. Business justification

An approver who must retype the disease name can mistype it into a public alert, and a notice
that cites another country's event press release reads as unofficial. Both meet a judge in the
alert demo.

## 3. Scope

**In scope:** the patches in §1, their tests, strings and the guidance asset's sources.

**Explicitly out of scope:**

- **What the model writes:** it still receives no case data and writes placeholders only
  ([`outbreak_alert_engine.md` §5](../../architecture/reports/outbreak_alert_engine.md#5-draft)).
- **Push copy:** a demo push keeps its "Demo" wording, since a lock screen shows no pill
  (Theo, 23 Nov).

## 4. Impact assessment

| Area | Impact | Notes |
|---|---|---|
| Data model (Firestore, Hive) | None | |
| Roles & case scoping | None | |
| Clinical safety | Changed | The approver reads the draft with code-filled facts; approval is still required, and approve-as-is still sends the machine text. Patient guidance cites standing MoH or WHO sources |
| AI service (prompts, models, thresholds) | None | The template fallback loses its demo prefix; the prompt is unchanged |
| Security (rules, App Check, RASP, secrets) | None | |
| Data protection (PHI, de-identification, model endpoints) | None | Rendering happens on the approver's phone from fields the alert already carries |
| Design system / UI consistency | Changed | The demo box becomes a status pill in the attention tone |
| Localisation (en, sw) | Changed | Filled in as the patches land |
| Existing data | None | Demo alerts delivered before the deploy keep their stored "Demo:" text |

## 5. Risk & rollback plan

**Risk level:** Medium: the alert path is clinical. Each patch is tested and certified on the phone.

**Rollback plan:** revert the patch's commit and redeploy the functions it touched.

## 6. Implementation plan

1. Trace each issue; the high-risk core (sources, drafts, approval) is written by the CTO, the
   screens by a coding agent, on disjoint files.
2. Full gates, then the Ebola loop again on the phone, then one commit per patch.
3. One pull request, reviewed to 5/5.

## 7. Testing & verification evidence

| Check | Result |
|---|---|
| `make analyze` / `make bloc-lint` | Pass — no issues |
| `make test` (`TZ=UTC`) | Pass — 3,965 |
| `make functions-test` | Pass — 703 |
| `make rules-test` | Pass — 250 (no rule changed) |
| `make spell` / `make release-check` | Pass — 0 issues / 36 checks |
| iOS simulator build | Pass, with the on-device guardrail change (entry 11) |
| Manual run | The Ebola loop on the iOS Simulator, 23 Nov, from order to delivered alert ([UAT-ITR-0001](../../testing/reports/UAT-ITR-0001-three-roles-end-to-end-2026-11-23.md)) |
| Certification | 2026-11-23, Theo |

## 8. Approval

| Role | Required when | Name | Date | Decision |
|---|---|---|---|---|
| Author | Always | Theo | 2026-11-23 | — |
| Engineering reviewer | Always, on the pull request | Greptile — pending | — | — |
| Clinical Reviewer | §4 flags clinical-safety impact or changes clinical wording | Covered by CTO | — | Pending |
| Security Analyst | §4 flags security impact | N/A | — | — |
| Compliance Officer | §4 flags data protection impact | N/A | — | — |
| Lead Designer | §4 flags design-system impact | Covered by CTO | — | Pending |

## 9. Post-implementation review

**Pre-review pass (23 Nov), before the pull request.** A local Greptile-style pass over the branch
found these, each fixed with a test that fails without the fix:

- **A redraft could put its alert back over another one.** The review bloc is shared and the
  redraft polls for up to 90 seconds; an approver who opened another alert meanwhile could have it
  replaced by the first. The poll now stops once another alert is current.
- **Asking for a new draft logged no analytics event** (the architecture's rule 7). It logs
  `alert_redraft_requested`, with nothing about the alert, once the server accepts it.
- **The two refusals had generic names** (`invalidState`), mapped app-wide to alert copy; they
  are now `alertRedraftLimit` and `alertRedraftClosed`, from the same server reason keys.

**Greptile round 1 (PR #30, 4/5).** Three findings, each fixed with a test that fails
without the fix:

- **P2: a demo alert looked real on the patient's home.** The home notice strip showed the stored
  headline with no mark once the text lost its prefix. It now carries the Demo pill, and a screen
  reader hears "Demo alert, not a real alert" first.
- **P2: an alert opened while drafting stayed on its spinner.** Only a redraft asked from this
  screen polled. Opening an alert that is `Drafting`, whoever started the redraft, now follows it
  the same way until its draft is in.
- **P2: three reporting reminders lost the Kenyan handbook.** Chikungunya, COVID-19 and mpox have
  no case definition, so their `-c1` bullet is the MOH 502/505 reminder, which had moved to the
  WHO source with the case definitions. They cite the handbook again, and a test holds both
  rules.

**Greptile round 2 (PR #30, 4/5).** One finding, fixed with a test that fails without the fix:

- **P2: the home strip's Demo pill had no large-text tests.** The strip now has them in `en` and
  `sw` at 1.0x and 2.0x on a 360 dp screen, and the Kiswahili 2.0x case found a real overflow: the
  pill sat in an `UnconstrainedBox`, so "Majaribio" ran 80 pixels past the narrow column. It now
  aligns to the start, keeping its own width and wrapping where room runs out.

## 10. Related records

- [CRQ-0006](./CRQ-0006-ui-ux-patches.md): the device run that first took the alert loop end to end.
- [`outbreak_alert_engine.md`](../../architecture/reports/outbreak_alert_engine.md).
