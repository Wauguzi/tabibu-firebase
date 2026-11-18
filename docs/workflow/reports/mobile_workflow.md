# Tabibu Engineering — Workflow

> This document describes Tabibu engineering as it runs today: who does the
> work, how a change moves from idea to the live demo, and what happens when
> something breaks. It follows an ITIL-aligned shape (change requests,
> incident reports, problem records), sized for a one-person build
> without dropping the discipline that makes the work traceable. Tabibu is a lean team: I am the
> CTO and the only engineer, and Greptile reviews every pull request as the
> second approver. Every other role is listed below as an open seat, so the
> process does not have to be redesigned when a pilot adds people.

| Field | Value |
|---|---|
| Sub-department | Engineering (mobile, AI service) |
| Parent department | Technology |
| Owner | Theo — CTO, Mobile Engineer |
| Status | Living |
| Last reviewed | 2026-11-15 |

## 1. Mission & scope

Engineering owns Tabibu end to end:

- **The Flutter app** — patient, doctor and pathologist workspaces from one
  codebase, submitted on iOS, with an Android APK for testing; it also builds for the
  web, which is not shipped.
- **Firebase** — Auth, Firestore, Storage, Cloud Functions, FCM, App Check,
  Remote Config, and the security rules that are the real data boundary.
- **The AI service** — the Cloud Functions jobs that call Gemini: the
  pre-read, the ordering risk check, the symptom summary, the report texts
  and the alert drafts. See
  [`ai_preread_service.md`](../../architecture/reports/ai_preread_service.md).
  The outbreak detector is code, not a model.
- **Model evaluation** — sensitivity and specificity on held-out labeled
  data, and time to preliminary report. See
  [`MODEL_EVALUATION_TEMPLATE.md`](../../testing/templates/MODEL_EVALUATION_TEMPLATE.md).
- **This `docs/` tree, the README, and the demo** — judges read the
  repository alongside the video and the live product.

Out of scope until a pilot:

- Real patient data. The build uses public datasets (PatchCamelyon,
  CAMELYON16, the NIH malaria set) and invented patients only.
- Clinical validation, a data protection impact assessment, and in-country
  hosting. These are the first pilot steps, not demo deliverables.
- Marketing and go-to-market work.

## 2. Org structure

**Status legend:** ✅ Staffed today · 🤖 Automated reviewer · ◻︎ Open.

| Department | Role | Name | Reports to | Status |
|---|---|---|---|---|
| Executive | CTO / Mobile Engineer (Flutter, Firebase, AI service) | Theo | — | ✅ |
| Engineering | Code reviewer and second approver on every pull request | Greptile | CTO | 🤖 |
| Design | Lead Designer | Open | CTO | ◻︎ |
| Clinical | Clinical Reviewer (pathologist or senior lab scientist) | Open | CTO | ◻︎ |
| Security | Security Analyst | Open | CTO | ◻︎ |
| Legal & Compliance | Data Protection / Compliance Officer (Kenya Data Protection Act, Digital Health Act 2023) | Open | CTO | ◻︎ |
| Data | ML Evaluation / Data Scientist | Open | CTO | ◻︎ |
| Engineering | QA Engineer | Open | CTO | ◻︎ |
| Engineering | Backend / ML Engineer | Open | CTO | ◻︎ |

**Sole authorship.** No person other than me writes code, designs screens,
or approves changes. Greptile is a tool, not a contributor. The open seats
above are placeholders for a pilot. Until someone fills
one, I cover that duty myself and the record says so (see §3).

**Not to be confused with the product's roles.** Patient, doctor,
pathologist and *alert approver* are user roles inside Tabibu, defined in
[`mobile_architecture.md` §11](../../architecture/reports/mobile_architecture.md#11-roles--authorization-model).
They are not seats in this org.

## 3. Responsibilities (RACI)

While a seat is open, I am Responsible for its duty and record it as
"covered by CTO" in the CRQ. A covered duty is never marked "N/A".

| Activity | R | A | C | I |
|---|---|---|---|---|
| Feature implementation | CTO | CTO | Lead Designer (open) | — |
| Code review | Greptile (on PRs) | CTO | — | — |
| UI/UX design & review | CTO, covering Lead Designer | CTO | — | — |
| Clinical wording: report templates, alert copy, patient explanations | CTO, covering Clinical Reviewer | CTO | Ministry of Health / WHO guidance as the reference | — |
| Security posture: rules, App Check, RASP, secrets, endpoint choice | CTO, covering Security Analyst | CTO | Greptile | — |
| Data protection: what leaves a case, what is cached, which endpoints see data | CTO, covering Compliance Officer | CTO | — | — |
| Model evaluation | CTO, covering Data Scientist | CTO | — | — |
| Incident response | CTO | CTO | — | — |
| Change approval (CRQ) | CTO | CTO | Greptile (PR review) | — |
| Documentation upkeep (`docs/`, README) | CTO | CTO | — | — |

## 4. Core workflow

The loop from idea to live demo:

1. **Idea / request.** Comes from the project plan, a defect found while
   testing, or a judging criterion the demo does not yet show. There is no
   ticket tracker; the plan's checklist is the backlog.
2. **Scoping.** Anything non-trivial gets a short plan before code starts.
   Changes that touch security rules, the AI service's prompts or thresholds,
   anything a patient reads, or the alert path get a
   [CRQ](../../crq/templates/CRQ_TEMPLATE.md). The CRQ is filled
   in as the work lands rather than as a pre-approval gate. With one
   engineer, a pre-approval gate would only mean approving my own plan twice.
3. **Implementation.** Follow
   [`mobile_architecture.md`](../../architecture/reports/mobile_architecture.md)
   and [`mobile_design_system.md`](../../design/reports/mobile_design_system.md).
   Reuse an existing pattern before inventing one. Blocs never import
   Flutter. Every model call goes through Cloud Functions. Run `make fmt`
   after every change.
4. **Self-review.** Check the change against the patterns already in the
   codebase, then read it in the context of its screen, not just the diff.
   For anything clinical, ask: does the person on the other end act on this
   before a qualified human has approved it? If yes, the change is wrong.
5. **Testing.** `make test` passes, and `make analyze` and `make bloc-lint`
   are clean. AI service changes also re-run the evaluation on the fixed
   held-out sample and file a new evaluation report if the numbers move.
6. **Certification.** Code is not committed until I have run it and
   certified it on a device or the simulator. Documentation-only
   changes are exempt. This is a hard gate.
7. **Commit and review.** Foundation work lands directly on `main`. Feature
   work happens on a branch, with a CRQ for each change it carries (a long
   branch has several), and reaches `main` through a pull request that lists
   them all:
   1. When the branch is complete, its title (Conventional Commits) and
      description are written from
      [`.github/PULL_REQUEST_TEMPLATE.md`](../../../.github/PULL_REQUEST_TEMPLATE.md).
   2. Greptile reviews it. Every finding is fixed, or answered on its thread;
      a finding accepted as a risk is recorded in CRQ §9, never silenced in
      `.greptile/rules.md`.
   3. **The merge bar is a 5/5 Greptile confidence score.** Below 5, the
      branch is reworked and re-reviewed, not merged.
   4. `CODEOWNERS` assigns every path to me, so I am requested on every pull
      request, Dependabot's included. Labels come from the template's choices
      and from `.github/labeler.yml`, using the set defined in
      `scripts/labels.sh`.
   5. The pull request merges with a merge commit, so every branch commit
      reaches `main` with the hash its CRQs cite; no branch is deleted. Right
      after the merge, the branch's CRQs record Greptile's rounds on `main`
      (§8's reviewer row, §9's findings), so the next branch starts from
      complete records.
8. **CI.** Every pull request to `main` runs `prod_apk.yaml` on Flutter
   3.47.8: format, code generation, analyze, bloc lint and tests, then a
   signed release APK to Firebase App Distribution; beside it, the
   functions' lint, build and type-check. The rules and functions emulator
   tests run locally (`make rules-test`, `make functions-test`). The spell check and the secret scan run
   locally through `make` before each commit (see
   [`mobile_architecture.md` §13](../../architecture/reports/mobile_architecture.md#13-cicd)).
9. **Release.** Merging to `main` drafts a release tagged with the branch's
   `pubspec.yaml` version, which is why every branch bumps it. Publishing
   with `make release-publish` marks it Latest. The entry runs on iOS, with
   one seeded account per role; the Android APK, in the Drive folder shared
   with the submission, is for judges who want to install the app.
10. **If something breaks**, see §7 and the
    [Incident Report](../../incidents/templates/IRP_TEMPLATE.md). A recurring
    or systemic cause is promoted to a
    [Problem record](../../problems/templates/PMF_TEMPLATE.md).

## 5. Tools & systems

| System | Used for |
|---|---|
| GitHub (`Wauguzi/tabibu-firebase`, public) | Source control, pull requests, GitHub Actions, `CODEOWNERS`, the label taxonomy (`scripts/labels.sh`) and path-derived labels (`.github/labeler.yml`) |
| GitHub Actions | `prod_apk.yaml` (quality gates, signed APK, App Distribution) and the license check (Very Good Workflows) |
| Greptile | Automated review of every pull request, the second approver. Its context is `.greptile/`: `files.json` points it at the governing docs, and `rules.md` summarises the conventions a diff does not show |
| Firebase Console | Auth, Firestore, Storage, Functions, FCM, App Check, Remote Config, Crashlytics, Performance |
| Firebase AI Logic | Gemini for the AI jobs: in the app (on-device where the platform has a model, cloud otherwise) and in Cloud Functions on the Agent Platform. No model key anywhere |
| Talsec portal | freeRASP threat events, once the app is wired to it |

## 6. Definition of done

A change is done when, in order:

1. It follows existing codebase patterns.
2. `make fmt` has been run, and `make analyze`, `make bloc-lint`,
   `make spell` and `make secrets` are clean (`make licenses` too, when
   dependencies changed).
3. `make test` passes.
4. For a UI change: tested live, on the golden path and the edge cases, at
   1.0x and 2.0x text scale, in English and Swahili, light and dark.
5. For an AI change: evaluated on the fixed held-out sample, with the result
   in an evaluation report if a number moved.
6. For a clinical-safety change: the §4 step 4 question has been answered in
   the CRQ, in writing.
7. I have run it and certified that it works.
8. The CRQ is filed (if one is due) and any affected doc in `docs/` is
   updated in the same commit.
9. Only then is it committed.
10. On a branch: Greptile has scored the pull request 5/5, and every finding
    is resolved. Only then is it merged.

## 7. Escalation & severity

The P1–P4 scale used by the CRQ, IRP and PMF templates. Tabibu's P1 list is
longer than a typical app's because some failures are clinical rather than
technical.

| Priority | Definition | Response |
|---|---|---|
| P1 — Critical | **A clinical-safety rule is broken:** an unsigned AI draft reaches a doctor or patient, an alert is delivered without approval, a patient sees a cancer result before the doctor marks it discussed, or patient-identifying fields leave a case into an alert event. Also: data exposure, a model call carrying data to a contributor (training-enabled) endpoint, or the live demo unusable during the judging window. | Immediate; drop everything. Take the affected path offline (Remote Config kill switch) before investigating. File an IRP the same day. |
| P2 — High | A major flow is broken in the live demo with no workaround: sign-in for a role, the pre-read never arriving, signing, alert approval. | Same-day fix. |
| P3 — Medium | A flow is degraded, or broken before it reaches the live demo. | Fixed before that flow ships or is recorded. |
| P4 — Low | Cosmetic issue or a rough edge in the UX. | Scheduled into the normal flow. |

A P1 caused by the AI producing something wrong is still a P1 even though no
code "failed". The rule is that no AI output reaches a person unreviewed, and
the incident is that rule failing.

## 8. Meeting cadence

| Meeting | Cadence | Attendees | Purpose |
|---|---|---|---|
| Daily plan check | Every day of the build | CTO | Tick off the day's work in the plan; slipped work comes out of the stretch goals first, never out of the pathologist workspace |
| Evaluation review | After any change to a prompt, model or threshold | CTO | Re-run the held-out sample; file an evaluation report if the numbers move |
| Documentation review | On every relevant commit, and a full re-read before submission | CTO | Keep `docs/` and the README in step with the code before judging |

## 9. Onboarding checklist (day 1)

1. Read this document, then
   [`mobile_architecture.md`](../../architecture/reports/mobile_architecture.md)
   and [`mobile_design_system.md`](../../design/reports/mobile_design_system.md),
   in that order: workflow, then architecture, then design.
2. Read the
   [threat model](../../security/reports/firebase_and_ai_service_threat_model.md).
   The clinical-safety rules there apply to every change.
3. Clone the repo, run `flutter pub get`, `make gen` and `make fmt`.
4. Run `make test` and confirm a clean pass before writing code.
5. Run the `development` flavor (`main_development.dart`). Never develop
   against `production`.
6. Read the watchlist in
   [`mobile_architecture.md` §16](../../architecture/reports/mobile_architecture.md#16-known-architectural-debt--watchlist),
   so new work does not collide with a known trade-off.

## 10. KPIs / health signals

The first three are the measures the project backbone document commits to;
the rest keep the build honest.

- **Tile- and cell-level sensitivity and specificity** on held-out
  PatchCamelyon tiles and NIH cells, against their labels.
- **Time to preliminary report**: seconds from a case opening to the draft
  on screen.
- **Pathologist edit rate**: the share of draft fields changed before
  signing. Reported from my own test reviews in the demo, and named as the
  first measure for a pilot.
- **Test suite pass rate** at commit: 100%, as a gate, not a target.
- **CI pass rate**: a failure on format or spelling means `make fmt` or the
  dictionary was skipped.
- **Demo run**: the whole three-minute flow runs end to end, without edits
  between steps, on the deployed build.
- **Documentation freshness**: every doc carries a "Last reviewed" date.

## 11. Change log

| Date | Change | Author |
|---|---|---|
| 2026-11-15 | Crafted for this repository. | Theo |
