# NEXT — Product Specification

**Status:** Authoritative. This document, not any chat transcript, defines the product.
**Last updated:** 2026-08-09

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

  I'm stuck   Not this   Why this?
        Everything    Add
```

No dashboard clutter. No metric tiles. No list competing with the recommendation.

---

### 4.3 Not this

The user must be able to reject the recommendation. Reasons offered:

- Can't do it right now
- Don't have what I need
- Need something shorter
- Need less effort
- Something else

A rejection applies a temporary penalty or contextual exclusion so the same task is not
immediately re-recommended without good reason. If no viable alternative exists, NEXT says so
plainly rather than recycling the rejected task silently.

---

### 4.4 Why this?

NEXT must always be able to explain itself in one short, intelligible sentence:

- *Due tomorrow and should take about 20 minutes.*
- *This unlocks the rest of the assignment.*

The recommendation is never presented as an unknowable oracle. The explanation is generated
from the deterministic ranking factors, so it is always available — including offline.

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

### 4.6a Settings — appearance

One switch: **Dark mode**, off by default (`DECISIONS.md` D-027).

NEXT does **not** follow the system appearance. That is a deliberate consequence of a two-state
switch rather than an oversight — an off position cannot mean both "light" and "whatever the
phone is doing" — and it is why the switch exists at all: someone whose eyes hurt in a bright app
should not have to change their whole phone to read a task.

The home-screen widget still follows the phone, because the system draws it. Settings says so
rather than leaving it to be discovered.

---

### 4.7 Everything

Secondary screen giving visibility and control. Sections: Today, Upcoming, No deadline,
Overdue, Completed.

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

Product UI is native SwiftUI. Generated imagery is for marketing, onboarding illustration where
justified, and App Store assets — not for coating every screen.

---

## 11. Accessibility — release blocking

Before release-candidate status, all of the following must hold:

- meaningful controls have useful labels
- VoiceOver traversal order is logical
- Dynamic Type works, including the largest sizes, without destroying key screens
- Reduce Motion is respected
- contrast is adequate
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

**NEXT Free** — manual tasks, deterministic recommendation engine, Focus, deadlines, reminders,
local persistence, basic Rescue, basic intelligent processing where economically reasonable,
basic widget, full accessibility.

**NEXT+** — advanced brain dumps, enhanced decomposition, advanced Rescue, Minimum Win
intelligence, adaptive replanning, personalisation, future sync, richer intelligence.

Prices are not final and require explicit justification before being set.

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

## 15. Store positioning (draft — not final)

- Line: *Know what to do next.*
- Description concept: *Dump everything on your mind. NEXT turns the mess into one thing you
  can actually start.*
- Screenshot narrative: Too much to do? → Dump it here. → NEXT finds what matters. → Do one
  thing. → Stuck? Make it smaller. → Plans fall apart. NEXT replans.

Marketing assets must truthfully represent the real app.

### Listing copy — drafted 2026-08-09, wording not yet chosen

Drafted so the screenshot proposal has words to sit beside; the final wording is chosen with the
screenshot direction rather than separately (**D-024**), because the two have to say the same
thing in the same voice. Every claim below is one the shipped app supports today — no cloud AI,
no account, and the offline promise are all currently true, and all three would have to be
re-checked if that changed.

**Title (30 characters max).** `NEXT — Know what to do next` fits at 27. Two alternatives worth
seeing side by side: `NEXT: One thing at a time` (25), and plain `NEXT` with the whole promise
carried by the subtitle.

**Subtitle (30 characters max).** Candidates, all inside the limit:
*Stop deciding. Start doing.* (27) · *One thing. The right one.* (25) · *For when it is all too
much.* (28)

**Description.** First three lines are what a student actually reads:

> You have too much to do and no idea where to start. NEXT gives you one thing.
>
> Dump everything on your mind into it — one line each or all in one go. NEXT works out what
> actually matters right now and shows you a single card with a single action. Start it, finish
> it, get the next one.
>
> **When you are stuck, say so.** NEXT does not tell you to try harder. It makes the thing
> smaller, gives you a first step you can do in five minutes, or finds you something else that
> is genuinely more urgent.
>
> **It never nags.** No streaks, no badge counting how far behind you are, no notification
> telling you off. Work you are late with quietly stops shouting instead of pinning itself to
> your screen for ever.
>
> **Everything stays on your phone.** No account, no sign-up, no tracking, no ads. NEXT does not
> use the internet at all, so it works on a train, in a basement, and on aeroplane mode.
>
> Made for students who are drowning in coursework and cannot face the list.

**Keywords (100 characters, comma-separated, no spaces).** Draft at 96:
`todo,adhd,student,focus,procrastination,overwhelm,homework,tasks,deadline,study,planner,revision`

Two deliberate omissions. Nothing claims NEXT is an AI app, because the shipping intelligence is
deterministic and offline and saying otherwise would be the exact misrepresentation D-024 and
D-014 both forbid. And nothing claims it treats or manages a condition — `adhd` appears as a
search keyword because it is what people search, and the copy makes no clinical claim anywhere,
which `PRODUCT_SPEC.md` §1 rules out.

---

## 16. Forbidden scope

Android · web app · macOS app · social network · public profiles · chat feed · leaderboards ·
friends · AI tutor · general AI assistant · GPA tracker · flashcards · note-taking platform ·
calendar replacement · LMS integration · Canvas integration · Google Classroom integration ·
habit-tracking system · therapy features · gamified pet · cloud backend · collaboration.

None of these are added on the grounds that they would make the app "more complete".
