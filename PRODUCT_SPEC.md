# NEXT — Product Specification

**Status:** Authoritative. This document, not any chat transcript, defines the product.
**Last updated:** 2026-08-12

---

## 1. Identity

NEXT helps overwhelmed students turn everything they have to do into **one clear thing they can
begin now**.

- **Promise:** Open the app. Know what to do. Start.
- **Principle:** Make the next action obvious.
- **Loop:** `CAPTURE → DECIDE → START → FINISH → NEXT`
- **Audience:** roughly ages 16–22 — late high school through undergraduate.

NEXT is an **execution assistant**. It is explicitly *not* a planner suite, project-management
tool, AI chatbot, mental-health application, social network, tutoring system, habit tracker,
or general productivity platform.

### Health positioning — hard boundary

NEXT does **not** diagnose, treat, manage, or claim to help with ADHD, anxiety, depression,
executive dysfunction, or any medical condition. No copy, metadata, or App Store text may imply
otherwise.

NEXT *does* address ordinary experiences: procrastination, overwhelm, poor prioritisation,
difficulty starting, tasks that feel too large, not knowing what to do first, missed deadlines,
and limited available time.

### Academic integrity — hard boundary

NEXT assists with *action*, not with *producing submittable work*.

- Allowed: break "write history paper" into steps.
- Not the product: generate a paper for submission.

---

## 2. Product invariants

These are not preferences. Violating one is a defect.

| # | Invariant | Meaning |
|---|-----------|---------|
| P1 | **One decision at a time** | Reduce the user's decisions; never add new ones. |
| P2 | **Starting beats organising** | The app exists to convert obligation into action. |
| P3 | **AI is advisory** | AI never silently becomes authoritative over consequential user data. |
| P4 | **Failure is a normal state** | A missed day triggers recalculation, never punishment. |
| P5 | **No productivity morality** | Never shame the user. |
| P6 | **AI earns its usage** | No LLM call where deterministic logic reliably suffices. |
| P7 | **Offline is supported** | Core functionality works with no network. |
| P8 | **Accessibility is architecture** | An accessibility defect in a core flow is a release blocker. |
| P9 | **Less is a feature** | Complexity is not added merely because it is possible. |

### Tie-breaker

When two valid solutions compete, ask: **which makes the next action more obvious?**
Prefer that one, unless it creates a real technical or accessibility problem.

---

## 3. Tone and personality

NEXT is a competent tool. It is not a parent, teacher, therapist, motivational speaker,
cartoon friend, or drill sergeant. Restraint is part of the identity.

- Write: `Start with questions 1–5.`
- Never write: `You've got this! You're amazing! 🌟`

Banned language patterns: "you failed", "you broke your streak", "you're falling behind",
"you missed your goal again", "we miss you".

---

## 4. Surfaces — NEXT 1.0

Primary:

1. Onboarding
2. Today / NEXT
3. Capture / Brain Dump
4. Capture Confirmation
5. Everything
6. Task Detail
7. Focus
8. Rescue / I'm Stuck
9. Settings

Supporting: contextual sheets, contextual permission prompts, paywall, notification actions,
widget, StoreKit test surfaces, debug interfaces excluded from production builds.

The navigation structure must stay small.

---

### 4.1 Onboarding

Three screens, then useful functionality.

1. *Too much to do? Put it here.*
2. *NEXT figures out what deserves your attention.*
3. *You only have to start one thing. The next thing.*

**Must not require:** account, email, username, profile, school, major, age survey,
productivity quiz, or personalisation questionnaire.

Permissions are requested contextually, at the moment they are needed — never as a wall of
prompts at launch.

---

### 4.2 Today / NEXT — the primary screen

The dominant object on screen is the single recommended action.

```
                    NEXT

              History essay
           Find three sources.
          Due Friday · ~20 min

              [  START  ]

     I'm stuck   Something else

         Everything    Add
```

No dashboard clutter. No metric tiles. No list competing with the recommendation.

**The two secondary rows are grouped by what they act on**, and the grouping carries meaning the
labels cannot. The first row is about *this recommendation*: two ways of saying it is not working.
The second is about the app, and is quieter and further away, because leaving this screen is not
one of the answers to the question the screen is asking.

That distinction is not cosmetic. Rendered as one row of four peers — which is what shipped
between sessions 5 and 14 — the four read as one undifferentiated set, and nothing on screen
indicated that two of them changed what you were looking at while the other two left it.

---

### 4.3 Something else

The user must be able to reject the recommendation. Reasons offered:

- Can't do it right now
- Don't have what I need
- Need something shorter
- Need less effort
- Another reason

The control was labelled `Not this` until session 14. The behaviour behind it is unchanged — the
reasons, the record, the penalty and its decay are all the same — and only the label moved, to one
that says what happens rather than naming a verdict. The fifth reason was renamed at the same time
and for a mechanical rather than an aesthetic reason: it read `Something else`, which is now the
name of the control that opens the list, and a button cannot share a label with one of the options
it offers.

A rejection applies a temporary penalty or contextual exclusion so the same task is not
immediately re-recommended without good reason. If no viable alternative exists, NEXT says so
plainly rather than recycling the rejected task silently.

---

### 4.4 Why this one

NEXT must always be able to explain itself in one short, intelligible sentence:

- *Due tomorrow and should take about 20 minutes.*
- *This unlocks the rest of the assignment.*

The recommendation is never presented as an unknowable oracle. The explanation is generated
from the deterministic ranking factors, so it is always available — including offline.

**It is shown on the card, not behind a control** (session 14). There was a `Why this?` link, and
for any task with a deadline it opened an alert repeating a line already printed on the card — the
card read `Due in 2 days · ~20 min` and the alert said `Due in 2 days.` It earned its place only
when a task had no deadline, which made it a control whose value could not be predicted before
tapping it.

The reason now takes whichever of the card's two slots fits its shape: a deadline joins the fact
line beside the estimate, and every other reason gets a line of its own as a sentence. Exactly one
slot, decided in one place, so it can be neither lost nor said twice.

---

### 4.5 Capture / Brain Dump

The user can type or paste unstructured text:

```
chem test monday, finish history slides friday, email professor, practice at 6
```

NEXT extracts structured tasks from it. Conventional manual entry is always available as a
fallback and is never second-class. Capture must not force the user to fill every field.
System dictation is supported through native APIs.

---

### 4.6 Capture Confirmation

Every consequential AI inference is confirmable — **deadlines especially**.

```
Input:  chem thing thurs and paper next friday

    Chemistry task — Thursday
    Paper — next Friday

    [ Looks right ]   [ Edit ]
```

Low-confidence or ambiguous deadlines ask the user rather than inventing certainty.

---

### 4.7 Everything

Secondary screen giving visibility and control. Sections, in the order they appear and each shown
only when it holds something: Overdue, Today, Upcoming, No deadline, Completed, Archived.

**Explicitly excluded:** Kanban boards, Gantt charts, nested workspaces, custom database
surfaces, tag engines, project-management structure.

---

### 4.8 Task Detail

Fields: title, notes, created, deadline, estimated duration, importance, status, next action,
substeps, reminder, source, recommendation metadata.

Actions: Start · Break it down · Edit · Complete · Delete.

Public priority control for 1.0 is **Normal / Important** only, unless testing proves more is
needed.

---

### 4.9 Focus

Entered by tapping START. Everything unrelated disappears.

Shows: the current action, the parent task where useful, an optional timer, and
Done / Pause / I'm stuck / Stop.

Timer presets: 5 · 15 · 25 · 45 minutes · no timer. NEXT is **not** a Pomodoro app; the timer
is optional and secondary.

---

### 4.10 Completion

Calm, positive, restrained. A small haptic and a quiet transition.

**Excluded:** XP, gems, streak pressure, punishment, leaderboards, reward economies.

After completion, NEXT immediately computes the next recommendation.

---

### 4.11 Rescue / I'm Stuck

A first-class feature, not a help page. Four entry points:

| Path | Response strategy |
|------|-------------------|
| I don't know how to start | Shrink the task to the smallest meaningful *physical* action. Reveal one step at a time — momentum matters more than exposing the whole decomposition. e.g. *Open the assignment instructions.* |
| It's too much | Hide the mountain, show one small step. e.g. *Forget the whole assignment for now. Find one source.* |
| I don't have enough time | Ask how long is available (5 / 15 / 30 / 60 min), then pick the highest-value action genuinely achievable in that window. |
| I just don't want to do it | No diagnosis, no lecture. Reduce friction. e.g. *Let's make the deal tiny. Do five minutes. Then you can decide whether to continue.* |

Rescue must never degrade into an open chatbot.

---

### 4.12 Minimum Win

When the ideal outcome is no longer realistically achievable, NEXT switches from *ideal
completion* to *highest-value achievable progress*.

A paper due tonight becomes: outline → introduction → first section → reassess.

This must never be used to encourage dishonesty or the submission of fabricated work.

---

### 4.13 Daily replanning

Unfinished work is recalculated on a new day. No shame language. A new day simply reassesses
what matters now.

---

### 4.14 Settings

Short, and every control says plainly what it does. For 1.0 it holds exactly:

- **Appearance** — one `Dark mode` switch, **off by default**. Two states, no follow-the-system
  option (**D-027**): NEXT does not track the phone's appearance, so somebody whose phone is dark
  opens NEXT in light until they turn this on. The home-screen widget still follows the phone —
  WidgetKit draws it in another process and an app cannot override it — and the footer says so.
- **Deadlines** — deadline reminders on or off, and how far ahead.
- **Daily** — the optional daily reminder on or off, and the hour.
- **Intelligence** — a cloud-processing consent switch, off by default, gating nothing today
  because nothing leaves the device.
- **Privacy** — where tasks are stored, and that there is no account.
- **NEXT+** — absent from a normal build for as long as NEXT+ unlocks nothing (**D-015**).

Reached from Everything, not from Today. Today's job is to show one thing.

---

## 5. The deterministic recommendation engine

A cloud LLM is **never** the sole decision-maker for what comes next. Ranking is deterministic,
centralised, documented, and unit-tested.

```
priorityScore =
      deadline urgency
    + importance weight
    + prerequisite / unlock value
    + overdue relevance
    + startability
    + contextual fit
    − friction
    − recent rejection penalty
```

All weights live in one central, documented, tuneable location. No magic constants scattered
through the codebase.

### Required edge-case behaviour

The engine must handle, deterministically and testably:

- impossible deadline
- task longer than the available time
- task with no deadline
- multiple equally urgent tasks (stable, explainable tie-break)
- repeatedly rejected task
- blocked task
- completed parent with pending child
- overdue task
- missing duration estimate
- no tasks at all
- all tasks currently unavailable

---

## 6. Intelligence

### AI may assist with

natural-language extraction · task decomposition · immediate-action generation · duration
estimation · Rescue simplification · brain-dump organisation · Minimum Win suggestions ·
ambiguity detection · natural-language explanation.

### AI must never own

database state · deletion · purchases · entitlements · notification scheduling · completion
state · deterministic ranking · navigation · payment state.

### Structured output

AI returns typed structured output, never free prose to be regex-parsed. Every response is
validated before any state mutation. Malformed output fails safe. **No AI response can corrupt
the local task database.**

Illustrative shape:

```json
{
  "tasks": [
    {
      "title": "Chemistry worksheet",
      "deadline": "2026-08-13T23:59:00Z",
      "estimatedMinutes": 30,
      "importance": "normal",
      "confidence": { "title": 0.97, "deadline": 0.72 }
    }
  ]
}
```

### Provider abstraction

Business logic must not couple to a vendor. An `IntelligenceProvider` abstraction sits between
the app and any model, with on-device, cloud, fallback, and mock implementations possible.
Provider selection research is recorded in [`DECISIONS.md`](DECISIONS.md).

### No-AI fallback — mandatory

NEXT remains genuinely useful when there is no internet, the provider is down, the user
declined intelligent features, the response fails validation, or the hardware lacks on-device
capability.

The fallback supports: manual task entry, storage, deterministic recommendation, Focus,
template-based Rescue, completion, reminders, and local state.

---

## 7. Data

Core task data is local-first. No remote database is introduced without a NEXT-specific
justification.

`Task` carries: id, title, notes, createdAt, updatedAt, deadline, estimatedMinutes, importance,
status, completedAt, nextAction, parent relationship, substeps, source, intelligence metadata,
lastRecommendedAt, rejection state, reminder metadata, ranking metadata.

State survives: app termination, device restart, an interrupted AI request, a failed
notification scheduling attempt, ordinary version upgrades, and offline use. A migration
strategy exists before release-candidate status.

---

## 8. Notifications

Sparse and useful.

- Appropriate: *Chemistry worksheet is due tomorrow.*
- Never: *We miss you!*

Categories: deadline reminders, an optional daily NEXT reminder, Focus completion.
Permission is requested contextually. The user has real controls.

---

## 9. Widget

At least one useful widget.

```
NEXT
Chemistry worksheet
Questions 1–5 · 15 min
```

Tapping deep-links into the app. No variant sprawl.

---

## 10. Visual direction

**Avoid:** gradients everywhere, AI sparkle icons, default mascots, pastel productivity-app
generic, stock-template SwiftUI look, decorative asset clutter.

**Identity:** calm · confident · modern · youthful without childishness · highly readable ·
tactile · restrained · distinctive.

Typography and hierarchy carry most of the identity. Motion reinforces
`NEXT → START → DONE → NEXT`, is functionally restrained, respects Reduce Motion, and never
becomes a barrier to operation.

**Two appearances.** Every palette token declares a light and a dark value, and every text pair
clears 4.5:1 in both. Which one is shown is the user's choice in Settings rather than the phone's,
and light is the default — see §4.14 and **D-027**.

Product UI is native SwiftUI. Generated imagery is for marketing, onboarding illustration where
justified, and App Store assets — not for coating every screen.

---

## 11. Accessibility — release blocking

Before release-candidate status, all of the following must hold:

- meaningful controls have useful labels
- VoiceOver traversal order is logical
- Dynamic Type works, including the largest sizes, without destroying key screens
- Reduce Motion is respected
- contrast is adequate in both the light and the dark appearance
- no meaning is conveyed by colour alone
- no essential action is gesture-only
- touch targets meet current platform guidance
- errors are announced accessibly
- timer state is accessible
- decorative images are hidden from assistive technology
- loading state is understandable

Automate what can be automated. Document precisely what still requires a physical device.
**Never fabricate a test result.**

---

## 12. Monetisation

Genuine value for free. No ads, no manipulative streaks, no forced subscription to discover
whether the app is useful, no dark patterns.

**NEXT+ is enhancement, never core access** (**D-034**). Everything NEXT does today is free and
stays free. No existing capability moves behind the paywall, now or later, to manufacture a paid
tier.

**NEXT Free — permanently.** Task capture, the deterministic recommendation and its explanation,
Focus, Rescue, brain-dump extraction, task decomposition, Minimum Win, deadlines and reminders,
local persistence, the widget where supported, Light and Dark appearance, full accessibility, and
offline operation. This is the product's promise, not an introductory tier.

**NEXT+ — genuinely enhanced or future capabilities only**, where they add convenience,
intelligence, recurring value, or carry ongoing cost: advanced or cloud-assisted brain-dump
interpretation; richer decomposition and action generation; smarter adaptive replanning; enhanced
Rescue and Minimum Win intelligence; future cross-device or iCloud sync; future automation and
personalisation; future premium intelligence that provides real additional value.

Those are **boundaries, not a backlog**. They say where a paid capability would be allowed to sit
if it were built. None is a requirement and none justifies expanding 1.0 scope. Note the shape of
the distinction: today's Rescue and Minimum Win are free forever, and only a genuinely *enhanced*
version of them could ever be premium.

**1.0 therefore gates nothing and sells nothing.** Applying the boundary to what exists leaves
every capability free, so the paywall stays unreachable in production rather than selling an
entitlement that unlocks nothing.

Prices are not final and require explicit justification before being set. A **Lifetime** purchase
must not imply unlimited lifetime access to per-request cloud AI; if premium intelligence creates
meaningful recurring cost, its economics are a separate design problem to solve before a lifetime
product is sold (D-016).

### Paywall rules

Appears only when the user intentionally invokes a premium capability. Never at launch.
No fake urgency, no misrepresented billing, no hidden prices, no monthly/annual confusion,
no cancellation dark patterns.

---

## 13. Privacy

Collect as little as practical. Excluded outright: advertising identifiers, behavioural
advertising, location tracking, contact harvesting, public profiles, unnecessary accounts,
selling user data.

AI requests transmit only the context required for that one operation — never the full task
history when one task suffices. Task text is never written into analytics or crash metadata.

Analytics, if any, are minimal and aggregate: `task_created`, `brain_dump_used`, `task_started`,
`task_completed`, `rescue_used`, `recommendation_rejected` — never task text. Shipping with no
third-party analytics is an acceptable outcome; crash visibility is likely more valuable.

Full detail in [`PRIVACY.md`](PRIVACY.md).

---

## 14. Success

NEXT succeeds when a user opens it, gets one useful recommendation, and starts doing something.
A successful session may last twenty seconds. **Do not optimise for time spent in the app.**

Candidate product metrics: first task created · recommended task started · recommended action
completed · Rescue usage · recommendation rejection rate. Rejection rate is likely the most
valuable signal for improving the ranking engine.

---

## 15. Store positioning — **approved and locked**

**Approved 2026-08-12 (D-038).** This is the copy of record. The measurable fields are held as
data in `scripts/validate-store-metadata.py`, which CI runs on every push; the two must agree, and
changing one without the other is the drift that script exists to make expensive.

**Positioning thesis.** Sell the situation, not the mechanism and not a feeling. NEXT is what a
student opens when six things are due and none of them has been started. Chosen over two
alternatives — a mechanism-first direction (*One thing at a time*) and a failure-state-first one
(*When You're Stuck*) — on search discoverability and conversion, and because situational claims
stay clear of the clinical boundary in §1 by construction. The full comparison, the evidence audit
that revised this copy, and the claims deliberately excluded are in
[`STORE_LISTING_PROPOSALS.md`](STORE_LISTING_PROPOSALS.md), retained as the historical record.

**Primary storefront language: English (U.S.)** (**D-036**).

| Field | Value | Limit |
|---|---|---|
| App Name | `NEXT: Homework & Deadlines` | 26 / 30 characters |
| Subtitle | `Six things due? Start one.` | 26 / 30 characters |
| Promotional Text | `Too much due at once? Put it all in, and NEXT will tell you what to do first.` | 77 / 170 characters |
| Keywords | `study,assignment,coursework,exam,essay,student,college,todo,task,procrastination,overwhelmed,school` | 99 / 100 **bytes** |
| Primary category | Productivity | |
| Secondary category | Utilities | |
| Description | below | 2058 / 4000 characters |

**App Tags** are not authored here. Apple derives them from this metadata plus AI plus human
curation, the developer can only deselect, and they are US-storefront-only — which is one of the
reasons the primary storefront is the one this copy is tuned for.

**Description.**

> Six things due this week. NEXT gives you one of them — one task, one action, and the reason it
> picked that one.
>
> Put it all in: type it, paste it, one line each or all in one go. NEXT reads it into separate
> tasks and asks you about any date it is not sure of, rather than guessing one.
>
> WHAT IT ACTUALLY DOES
> • Takes a whole brain dump at once, typed or pasted
> • Reads the dates it recognizes, and asks instead of guessing when it does not
> • Picks one thing to do now, and tells you why it picked it
> • Breaks a task you are avoiding down to one physical first step
> • Opens a single Focus screen with that one action on it and an optional timer, then leaves you
> alone
> • Keeps the whole list in Everything, sorted into Overdue, Today, Upcoming and No deadline, for
> when you do want to see it
>
> THE ESSAY YOU CANNOT FACE
> Tap I'm stuck and say what is in the way.
> • I don't know how to start — NEXT gives you the smallest physical action, one at a time, so you
> never see the whole mountain
> • It's too much — it hides the mountain
> • I don't have the time — say how much you have, five minutes or fifteen or thirty, and NEXT
> finds the most useful thing that genuinely fits, or tells you plainly that nothing does
> • I just don't want to — no lecture. Do five minutes, then decide whether to carry on
>
> WHEN IT IS TOO LATE TO DO IT PROPERLY
> An assignment you can no longer finish in the time left gets a smaller version that is still
> worth doing — outline, then introduction, then first section — and a time to come back and
> reassess. One whose deadline has already passed says so, without a lecture, and still offers you
> something you can do now. Late work quietly stops shouting instead of pinning itself to your
> screen forever.
>
> NO STREAKS, NO GUILT, NO ACCOUNT
> NEXT never tells you that you have fallen behind, broken anything, or let yourself down. There
> is no sign-up, no email address, no tracking and no ads. It makes no network requests of its
> own, so it works with no signal at all, and nothing you write ever leaves your phone.
>
> For high school and college.

**What this copy deliberately never says**, each because the repository cannot support it: no AI
of any kind, because the only shipped provider is deterministic and offline; nothing clinical, per
§1; no grades, marks or study outcomes; no sync, iPad or Mac; no general natural-language
understanding, because `DatePhraseParser` recognises a handful of phrase shapes and refuses the
rest on purpose; nothing about NEXT+, which sells nothing in 1.0; nothing about the widget, until
its content has been observed on a device (`RELEASE_GATED.md` B1a); and never "fully accessible",
which `TESTING.md` names as a forbidden phrasing.

Two precise wordings that were argued over and are load-bearing. **"makes no network requests of
its own"** rather than "does not use the internet": NEXT's own code makes none and CI fails if any
shipped source names a networking API, but the app constructs a StoreKit transaction listener at
launch and Apple's daemon is not NEXT's to observe. And **"asks you about any date it is not sure
of, rather than guessing one"** states the design position — a wrong deadline is worse than a
missing one — instead of implying an understanding the parser does not have.

### Screenshots — approved and locked

Six frames, CI-captured from the running app (`ScreenshotCaptureUITests`), composited onto the
Chroma grounds by `scripts/compose-store-screenshots.py`, in listing order. The set was approved by
**D-031** and frame 6 was **recaptured and re-approved** on 2026-08-12 (**D-037**, locked by
**D-039**) after D-030 changed the state it shows. Frames 1–5 are byte-identical to the originally
approved set.

  | # | Frame | Caption |
  |---|---|---|
  | 1 | Capture, mid-dump | *Put it all down at once.* |
  | 2 | Today, chosen by deadline | *One thing, and why.* |
  | 3 | Today, chosen because it is startable | *Not the project. The first move.* |
  | 4 | Focus, running | *Then it gets out of the way.* |
  | 5 | Rescue | *Say what's in the way.* |
  | 6 | Today, overdue | *Behind? No lecture.* |

  Each caption describes what is visible in its own frame and claims nothing the frame cannot
  show. Frames 1 and 2 carry the whole proposition on their own, because that is how many a
  shopper sees at thumbnail size in a search result. Frames 2 and 3 are the same screen and two
  different selection reasons — a deadline, and a task being startable — which is what makes the
  repetition worth its place.

  **Frame 6 must show the shipped overdue state**, and that is a requirement rather than a
  description of one capture. It carries `This is past its deadline.` and the surviving
  `What can I still do?` affordance, both of which arrived with **D-030**. The pre-D-030 frame —
  which read `There is not enough time left to finish this.` and showed no affordance — is **no
  longer a canonical store asset** and must not be uploaded. `ScreenshotCaptureUITests` asserts
  both before the shutter, so a frame missing either cannot be captured at all.

  Two deliberate silences. Frame 6 claims only the absence of a telling-off, and nothing about
  recovering late work — not because there is no route, but because Rescue re-ranks and the step
  it offers may belong to a different task (D-030). And **no frame is dark and no caption mentions
  Dark mode**: it ships and is measured (D-027, D-029), which is a reason it *may* be claimed, not
  a reason it should be.

Marketing assets must truthfully represent the real app.

### The 2026-08-09 draft is superseded

An earlier draft of the title, subtitle, description and keywords sat here from 2026-08-09 with
alternatives beside it. It is **superseded by the approved copy above** (D-038) and has been
removed rather than left below it, because a spec section holding two listings is one where the
wrong one gets used. It survives in Git history and in `STORE_LISTING_PROPOSALS.md`.

Three things it got right and the approved copy keeps: no claim that NEXT is an AI app; no
clinical claim anywhere; and the offline and no-account promises stated at a width the code
supports.

One thing it got wrong, recorded because the reasoning is worth keeping. Its keyword field
included `adhd`, argued as "a search term rather than a claim". The approved field **excludes**
it: App Review 2.3.7 treats irrelevant keyword terms as grounds for modification or rejection, and
an app that makes no ADHD claim anywhere — as §1 requires — is not an ADHD app. Reinstating it
would be a deliberate owner decision against a stated risk, not a default.

---

## 16. Forbidden scope

Android · web app · macOS app · social network · public profiles · chat feed · leaderboards ·
friends · AI tutor · general AI assistant · GPA tracker · flashcards · note-taking platform ·
calendar replacement · LMS integration · Canvas integration · Google Classroom integration ·
habit-tracking system · therapy features · gamified pet · cloud backend · collaboration.

None of these are added on the grounds that they would make the app "more complete".
