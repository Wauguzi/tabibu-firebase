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
3. **The Results filters did not add up.** "All" counted every result, but only "With your
   doctor" and "Shared" had pills, so results still waiting for the pathologist made All look
   inflated. A "Waiting" pill now counts them, and Waiting, With your doctor and Shared always
   add up to All. Certified on the iPhone, 17 Nov.
4. **A profile with a stock photo could not be saved.** The profile rules accept a photo only
   as the project's own Storage download URL, on every save, but the seed stored the demo
   practitioners' stock photos as links, and one was set by hand on the demo patient, so each
   of those accounts was refused (`permission-denied`) on any profile save. The seed now copies
   each photo into `profilePictures/{uid}/` first, and `functions/scripts/fix-demo-photos.ts`
   (dry by default, `--live` behind the project confirm) moved the 17 stored links: 1 patient,
   16 doctors and pathologists. No rule changed. Run on the live project and the patient's
   save certified on the iPhone, 17 Nov.
5. **Editing the patient's profile took a detour, and a save gave no word.** The pencil on
   the Profile card opened a read-only "My profile" screen, whose own pencil led to Edit
   profile. The pencil now opens Edit profile directly, "My profile" and its route are gone,
   and the patient's card draws on the same teal pattern as the practitioners'. After a save
   the screen sometimes came back: the router re-ran its sign-in guard on every session
   change, and a profile save changes the session, so the guard could restore the screen the
   save had just closed. The guard now runs again only when what it reads changes (signed in
   or out, and the role claims). A save now returns to the Profile tab with "Profile updated",
   for patients and practitioners. Certified on the iPhone, 17 Nov.
6. **The app lock offered a fingerprint/face switch that could not be turned on, and its
   screens misled.** Biometrics were built as an extra way in on top of the PIN, so the switch
   stayed disabled until a PIN existed. The lock is now one method at a time: off, a 4-digit
   PIN, or fingerprint/face, stored as one value (an older phone holding both reads as the
   PIN). Turning fingerprint/face on or off, or switching from it to a PIN, needs the phone's
   own prompt first; a phone with none enrolled is refused with the shared notice, which
   recommends the PIN; a cancelled prompt changes nothing. Unlocking with fingerprint/face
   offers the phone's passcode as the fallback; the PIN keeps its five-attempt sign-out. The
   prompt's permission to set a PIN in its place ends when that screen closes or the app goes
   to the background. Alongside: `NSFaceIDUsageDescription` added, without which iOS refuses
   Face ID; "Lock after" shows the chosen delay as an on switch instead of forward arrows; the
   Profile row names the method that is on, not "4-digit PIN" for both; a saved PIN closed a
   notice instead of its own screen, leaving the person on Create PIN (two listeners on one
   success), and now returns to App lock with "PIN set"; and "Forgot PIN?" opened its sheet
   behind the lock cover, so the tap looked dead, and now asks inside the cover, with Sign in
   again (which clears the PIN with the session) or Back. Certified on the iPhone 14, 17 Nov.
7. **The privacy policy's draft line led the page and carried an old date.** "Draft · last
   updated 27 Oct 2026" sat above the policy; it now closes it, below the last section, and
   reads 17 Nov 2026, for patients and clinicians. Certified on the iPhone, 17 Nov.
8. **A doctor without a photo showed a box within a box.** The directory card (Home and Find a
   doctor) drew the avatar's own paler tile inside its photo square, which read as a gradient.
   The initials now sit directly on the square, at their earlier size, using the avatar's own
   rule (`Avatar.initialsOf`, no title); they also sit under a photo, so one that fails to load
   shows them rather than a blank. Certified on the iPhone, 17 Nov.
9. **The County and Sub-county sheets left white space and blurred their rows.** The shared
   select sheet (My area, and sign-up's area and title pickers) capped its list at 60 % of the
   screen inside a near full-height sheet, and drew each row as a separate card. The list now
   reaches the sheet's bottom edge on any phone, with the search fixed above it and the list
   still lazy, and the rows sit on the sheet itself, divided by the Profile menus' hairline,
   with no card, shadow or fill: a check marks the choice, announced as selected. Note for
   review: the sheet measures the space below the list after layout, and hands a downward
   drag at the list's top to the sheet's own scroll position so drag-to-dismiss still works,
   because `TabibuBottomSheet` gives its content no fixed height; letting that sheet host a
   list directly would be the cleaner change, deliberately not made in a patch. Certified on
   the iPhone, 17 Nov.
10. **Eight seeded directory doctors had no photo, and one photo cut off a head.** The demo
    directory data (`functions/data/demo_directory.json`) now gives every seeded doctor a
    photo of someone who looks like a clinician and matches the name's gender, with varied
    skin tones and no face used twice; Lucy Wambui's is replaced; and Kevin Omondi becomes
    Dr. Arjun Mehta, a Kenyan Asian name, since no unused free photo of a dark-skinned male
    doctor could be found. Each photo is a stock model from Pexels or Unsplash, its author,
    source and licence read from the photo's own page. `functions/scripts/apply-directory-photos.ts`
    applied the file to the live directory without a reseed (dry by default, `--live` behind
    the project confirm, seeded accounts only, photos copied into Storage): 9 of 9, 17 Nov.
    Two accounts that were not seeded were left alone. Certified on the iPhone, 17 Nov.
11. **The slide pixel-size field was invisible until tapped.** On the order's slide card the
    field's fill is the card's own white, and only an uploaded slide drew a hairline. Every
    row now draws the hairline the app uses for fields on white surfaces (as on the case notes
    sheet and Sample received); the uploaded row stays locked. The first patch of the doctor's
    run. Certified on the iPhone, 17 Nov.
12. **Clinic hours used Material's clock dial, and its times did not read as fields.** Opens and
    Closes now open the app's Cupertino wheel (as for the date of birth), in half hours only,
    since the rules take :00 and :30; the old code rounded a free pick. The times are outlined
    picker fields: `PickerField` gains `bordered`, the hairline a text field on a sheet uses.
    Certified on the iPhone, 17 Nov.
13. **A tapped slide looked like it floated.** The full-slide view is a full-screen dialog,
    but the dialog kept to the safe area by default, so the dimmed screen showed above and
    below it. It now runs edge to edge, with its own safe area inside. Certified on the
    iPhone, 17 Nov.
14. **Opening a case logged a denied score read.** Before the pathologist scores a pre-read
    run there is no score document; the rule for `prereadScores` (and `reportProvenance`)
    read `resource.data` unguarded, so the read was denied rather than answered as missing.
    The app already treated a missing score as normal, so nothing broke, but each open logged
    a red failure. The case's own pathologist now reads a missing document as not found;
    no one else gains a read (RT-203, and RT-101 unchanged). Rules deployed 17 Nov; the log
    certified clean on the iPhone.
15. **Text fields on bottom sheets were invisible until tapped.** A field's fill is the
    sheet's own white, and only two sheets drew the field hairline. Every sheet field now does:
    amend reason and addendum, the explanation edit, the region question, decline booking,
    move, cancel, and the alert edit and reject sheets. Certified on the iPhone, 17 Nov.
16. **A tapped slide's full view had no order and no double tap.** It now carries the order
    number as its title and the slide's details beneath, as the order header does, and a double
    tap zooms in about the tapped point (a second returns), since a pinch can be taken by the
    page. Certified on the iPhone, 18 Nov.
17. **Accept and Sample received looked frozen for a second.** Each write is followed by a
    reload of the case, and the button stopped spinning at the write; it now spins until the
    next screen is ready. Certified on the iPhone, 18 Nov.
18. **The slide's controls.** The region read is a short **✦ Ask AI** at the slide's bottom
    right (screen readers still hear "Ask AI about this region"), no longer wrapping under the
    heat-map toggle; zoom is two round 48 dp buttons with a gap, zooming about the centre of
    the view instead of the image's corner. Certified on the iPhone, 18 Nov.
19. **Ask AI's answer lives in the workspace.** The sheet only asks (a "Question" field, its
    hint, only the Ask button spinning); the answer goes to a panel under the slide, "Ask AI
    draft" in the AI frame with its model and template showing and "Disclaimer: Ask AI draft,
    not a result"; before any ask the panel says how to use it, and a new ask replaces the last.
    The pre-read card's "not a result" row became a disclaimer inside the card. Both AI
    summaries open with their models listed and keep the person's choice across scrolling
    (`AiDraftFrame.initiallyExpanded`, kept in `PageStorage`). The answer is held in the
    screen's state only: never saved, no copy action, never in a write, cleared when the case
    changes, and only for the case's accepted pathologist (S-8, CRQ-0005). Certified on the
    iPhone, 18 Nov.
20. **Reporting was one long page whose order was enforced but not shown.** It is now two
    steps: 1 · AI score, then 2 · Diagnosis, which waits until the score is saved and says why;
    saving folds the score to "Done · overall n of 5" behind its arrow and opens Diagnosis. The
    six required score questions carry the required mark, and their answers sit on one
    scrolling line. Once Diagnosis opens on a scored case with a ready pre-read and an untouched
    draft, the AI's diagnosis and comments are filled in to be edited ("Edit the remarks before
    you sign"), replacing the Start from AI / Write my own buttons; the rules already allow
    that start only after a score, the pathologist's own text is never replaced, revisions never
    get it, and the report reaches the doctor only when signed (S-2). Critical finding and
    notifiable diseases are switches. Certified on the iPhone, 18 Nov.
21. **The Signed tab counted the wrong set.** Its card counted today under every pill but This
    week, so Notifiable showed "0 · Signed today" over older cases. It now counts what the pill
    shows, hides at zero, and an empty pill says so below the pills. Certified on the iPhone,
    18 Nov.
22. **A notice blocked the screen until it went.** Every notice ("Draft saved" and the rest)
    was a modal route with an invisible full-screen barrier, so scrolling and taps hit the
    barrier. It now sits on the root overlay with no barrier: the screen keeps working, a pop
    can no longer close a notice in place of a screen (the cause of two earlier patches), and
    screen readers hear it as a live region. Certified on the iPhone, 18 Nov.
23. **A shared case opened from the inbox was "not found".** The code screen never loaded the
    doctor's cases, so a case shared before the Cases tab had synced could be neither named nor
    opened. The screen now refreshes the cases on open; until they arrive, the code field is off,
    Open report waits with its loading dots, and a full code does not submit itself. Certified
    on the iPhone, 18 Nov.
24. **A refused explanation language vanished.** The server writes the English and Kiswahili
    explanations separately, and its safety check can refuse either one (`AdvicePhrase`). The
    review folded both into one state, so a refused language was simply missing. Each language
    now stands on its own: a refused one says "The English explanation couldn't be written, so
    it was not sent to the patient." with Try again, which asks the existing `requestReportText`
    for that language only. The new draft still waits for the doctor's approval, and the refused
    text and its reason are never shown. Approve as is keeps its colour and shows the loading
    dots while it runs; a loading primary button no longer turns grey anywhere in the app.
    Certified on the iPhone, 18 Nov: both drafts were refused after Mark as discussed, Try again
    brought both back, and both were approved as is.
25. **Listen to this summary never played.** The player saved every clip as `.m4a`, and iOS
    picks the decoder from the file name, so the speech audio (WAV) failed to load in either
    language; the recording cues, also WAV, were silent the same way. A clip that opens with a
    WAV header is now saved as `.wav` (`audio/wav` on the web), and voice notes keep `.m4a`. The
    listen path logs each failure in debug builds with its type and lengths only, never the text
    or the audio, and the speech service refuses a reply that is not WAV by name. Certified on
    the iPhone, 18 Nov: the patient hears the explanation in the app's language, English or
    Kiswahili.
26. **Report measurements read as database keys.** "tumourAreaPercent" ran into "26.67" in a
    fixed 120 dp column, and tile counts showed as "12.00". Each measurement now has a name in
    English and Kiswahili, with its unit ("Tumour area 26.67%", "Largest focus 1.20 mm", tile
    counts whole), shared by the doctor's report, the full report, the PDF and the pathologist's
    pre-read card. A unit the report states still wins, an unknown key reads as words, and the
    label column keeps a gap before its value. Certified on the iPhone, 18 Nov.
27. **The README.** It no longer mentions the web build: the entry is on iOS, with the Android
    APK and the account setup in the Drive folder. A table and the How it works column say where
    each AI job runs (on the phone, from the app to the cloud, or in Cloud Functions) and on
    which model, and the diagram shows each AI call. The lines saying speech and the region read
    ship switched off are gone.
28. **The docs matched the old plan.** The architecture, AI service, design system, workflow,
    notifications and threat model documents presented a web demo as shipped and said voice
    input and the region read were off. They now say the entry is iOS with an Android APK (the
    code still builds for the web), that the in-app AI calls are on in the live project, that every server job runs on
    `gemini-3.8-flash`, and that each explanation language can be asked for again.
29. **The app's own defaults lagged the live project.** Voice input and the region read
    defaulted off in the app (and a config that could not be read hid them), while the live
    Remote Config had both on. Both now default on, as the listen switch already did. The
    server's `voice_input_enabled` keeps failing closed when its template cannot load, so a
    transcript is still refused there.

## 2. Business justification

These are the rough edges a judge meets in the first minutes as each role. A message that
says why something is unavailable, and when it will be, replaces a generic failure.

## 3. Scope

**In scope:** the patches listed in §1, their tests and the strings they add.

**Explicitly out of scope:**


- **Push on the iPhone:** the free Personal Team cannot add the push entitlement, so APNs
  issues no token; the in-app inbox still works and Android receives pushes (CRQ-0004 §3).
- **Server rules:** none beyond patch 14's missing-document read; the app explains the server's
  existing refusals.

## 4. Impact assessment

| Area | Impact | Notes |
|---|---|---|
| Data model (Firestore, Hive) | None | |
| Roles & case scoping | Reviewed | The chat rule is unchanged; patch 14 lets the case's own pathologist read a not-yet-written score or provenance as missing, no one else |
| Clinical safety | Changed | Patches 19 and 20: where Ask AI's answer appears (screen state only, never saved), and the report pre-filled from the AI draft after the score, signed before it reaches anyone. Patch 24: a refused explanation language can be asked for again; the new draft is still approved by the doctor before the patient sees it |
| AI service (prompts, models, thresholds) | None | |
| Security (rules, App Check, RASP, secrets) | Changed | Patch 4 brings stored photo URLs in line with the existing profile rules, which are unchanged. Patch 6 changes the app lock: one method at a time, fingerprint/face no longer behind a PIN, the phone's passcode its fallback (threat model T-11) |
| Data protection (PHI, de-identification, model endpoints) | None | |
| Design system / UI consistency | Extended | `GroupedRow` gains a caption and a disabled state: muted text, the neutral icon tone, no chevron, announced as a disabled button with its reason. `TabibuButton.primary` keeps its colour while loading (patch 24); `SummaryCardRow` keeps a gap before its value (patch 26) |
| Localisation (en, sw) | Added, removed | Added `chatRowWaitingCaption`, `errorConversationUnavailable`, `resultsFilterWaiting`, `profileSavedToast`, `explanationLanguageFailed`, the eight `reportMeasurement…` names; removed the six strings only "My profile" used |
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
| `make test` (`TZ=UTC`) | Pass — 3,806 after patch 26 |
| `make functions-test` | Pass — 664, with the photo URL check and the Storage copy (patch 4) |
| `make rules-test` | Pass — 249, with RT-203 (patch 14) |
| `make spell` | Pass — 0 issues |
| Red proofs | Patch 1: the disabled row, the requested state and Back instead of Retry each fail with the fix removed. Patch 2: the one-line test fails against the old wrap. Patch 6: each lock guard (enrolled check, cancel, off prompt, PIN check, prompt before the PIN hash goes, older store, passcode fallback, the permission's end), the PIN-set return and the reachable Forgot PIN panel fail with their fix removed. Patch 23: the refresh on open and the busy field and button. Patch 24: the kept failed language, the `requestReportText` call, the refused retry, the failed line and the loading colour. Patch 25: the WAV name and type, each debug log, the WAV check and the `sw` code. Patch 26: the names and the gap |
| Manual run | Patches 1 to 26 certified on the iPhone 14, 17–18 Nov; the patient's and doctor's sides are done, the pathologist's under way |
| Certification | Pending the end of the run |

## 8. Approval

| Role | Required when | Name | Date | Decision |
|---|---|---|---|---|
| Author | Always | Theo | 2026-11-17 | — |
| Engineering reviewer | Always, on the pull request | Greptile — pending | — | — |
| Clinical Reviewer | §4 flags clinical-safety impact or changes clinical wording | Covered by CTO | 2026-11-18 | Approved: the AI draft is framed as AI until edited, starts only after the score, never replaces the pathologist's text, and reaches the doctor only when signed; Ask AI stays unsaved and pathologist-only |
| Security Analyst | §4 flags security impact | Covered by CTO | 2026-11-17 | Approved: photos move into the owner's Storage folder, the rules stay strict; the lock's fallback is the phone's passcode, by decision, and every change of method needs the current one first; the score rule answers missing only to the case's own pathologist |
| Compliance Officer | §4 flags data protection impact | N/A | — | — |
| Lead Designer | §4 flags design-system impact | Covered by CTO | 2026-11-17 | Approved: the disabled row follows the disabled button's muted colour |

## 9. Post-implementation review

Filled in after the run.

## 10. Related records

- Architecture/design references: [design system](../../design/reports/mobile_design_system.md), [CRQ-0004](./CRQ-0004-device-run-fixes.md), [CRQ-0005](./CRQ-0005-ai-logic-templates-and-speech.md), [threat model](../../security/reports/firebase_and_ai_service_threat_model.md) (T-11)
- Evaluation report(s): none
- Related Incident Report(s): none
- Related Problem record(s): none
