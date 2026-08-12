# NEXT — App Store listing: three positioning directions

**Status:** **Direction 2 is the owner's working selection** (2026-08-12), with the name and
subtitle `NEXT: Homework & Deadlines` / `Six things due? Start one.`. The copy itself is **not yet
approved** — §9 is an evidence audit of the selection and proposes **direction 2R**, which keeps
the name and subtitle exactly and revises the rest. Directions 1 and 3 are kept until one of 2 and
2R is approved, then this file is reduced to the winner.

This is the D-024 checkpoint for the listing wording, which is the last piece of store copy: the
screenshot direction, the six frames and the six captions are approved and locked (**D-031**), and
frame 6 has been recaptured under D-031's own reopening rule (**D-037**, §10).

**Date:** 2026-08-12 · **Decision:** owner's, one of three, then `PRODUCT_SPEC.md` §15 is replaced
with the selection.

Every character- and byte-limited field below is validated by
[`scripts/validate-store-metadata.py`](scripts/validate-store-metadata.py) against Apple's
published limits rather than counted by eye. The script holds the copy as data; this file is the
reasoning. Run it:

```bash
python scripts/validate-store-metadata.py
```

---

## 1. The product evidence

Everything in this section is read out of the repository, not remembered. It is the constraint on
what the listing may say.

### What NEXT 1.0 actually does

| Capability | Status | Where proven |
|---|---|---|
| Capture a brain dump, split it into separate tasks, read a small set of date phrases | Shipped | Tier 1 `Intelligence`; frame 1 |
| Manual task entry, never second-class | Shipped | Tier 2 |
| Confirm anything the reading was unsure of, deadlines especially | Shipped | Tier 1 + Tier 2 |
| Recommend exactly one task and one action, deterministically | Shipped | Tier 1 `Ranking`, 568 tests |
| Print the reason for the choice **on the card** | Shipped | `RecommendationCardCopy`, Tier 1/2 |
| Reject the recommendation with a reason; decaying penalty; re-rank | Shipped | Tier 1 + Tier 2 |
| Focus: one action, optional timer (5/15/25/45/none), Done · Pause · Stop · I'm stuck | Shipped | Tier 2 UI |
| Rescue: all four stuck paths, one step at a time, offline | Shipped | Tier 1 `Rescue` |
| Minimum Win: a smaller outcome when the deadline is unreachable, with a reassess time | Shipped | Tier 1 `MinimumWin` |
| A passed deadline says so and still routes to something doable | Shipped | D-030, Tier 1 + Tier 2 |
| Everything: Overdue · Today · Upcoming · No deadline · Completed · Archived | Shipped | Tier 2 |
| Task Detail, including Break it down | Shipped | Tier 2 |
| Deadline reminders and an optional daily reminder; tapping one opens that task | Shipped, **delivery device-gated** | Tier 1/2; `RELEASE_GATED.md` B5 |
| Dark mode, one switch, light by default | Shipped and **measured** | D-027/D-029, `AppearanceUITests` |
| Home-screen widget | Ships, **end-to-end unverified** | `RELEASE_GATED.md` B1a |
| No account, no network request of NEXT's own, no analytics, no third-party SDK, no logging | Shipped, **CI-enforced** | `scripts/lint-shipped-code.sh` |

iPhone only, portrait only, iOS 17.0 and later (`project.yml`, D-004). Display name `NEXT`,
bundle `com.nextapp.next`.

### The primary user problem

Not disorganisation. **Not starting.** A student who already knows what they owe, opens a list,
reads it, and does nothing. `PRODUCT_SPEC.md` §1 names the experiences NEXT addresses:
procrastination, overwhelm, poor prioritisation, difficulty starting, tasks that feel too large,
not knowing what to do first, missed deadlines, limited time.

### What differentiates it — from the shipped product, not from ambition

1. **It shows one thing and refuses to show a list.** The recommendation is the whole screen.
   Everything else is one tap away and deliberately quieter.
2. **It says why**, in one sentence, from deterministic factors — so the explanation exists
   offline, always, and cannot be a black box.
3. **Rejection is a designed interaction, not an absence.** Five reasons, a decaying penalty,
   an honest "nothing else fits" when there is no alternative.
4. **Being stuck is a supported state.** Rescue is a first-class surface with four paths, not a
   help page. No competitor screenshots this.
5. **Being late is a supported state.** Lateness decays (D-020) instead of pinning work to the
   screen; a passed deadline is stated once, as a fact, and still offers a route.
6. **The unfinishable gets a smaller version worth doing** (Minimum Win) rather than a guilt trip.
7. **It is deterministic and local.** No model, no server, no account, no telemetry — and that is
   enforced by CI, not by intention.
8. **It sells nothing.** 1.0 gates nothing and has no reachable paywall (D-034, D-035).

Against the field: task managers give you a better list; calendars schedule; focus timers assume
you have already started; AI productivity apps need an account, a network and a subscription.
NEXT's whole claim is the twenty seconds between opening the app and starting work.

### Claims that are directly supported

One recommendation at a time · the reason on the card · rejecting it and getting another ·
brain-dump capture into separate tasks · confirmation of uncertain deadlines · four stuck paths ·
smaller first steps · a time-budget answer ("I have 15 minutes") · a smaller achievable outcome
when the whole thing no longer fits · a passed deadline stated without a lecture · Focus with an
optional timer · no streaks, badges, XP or shame language · deadline and daily reminders you
control · light and dark · no account, no sign-up · no tracking, no ads, no analytics · works with
no network · nothing you write leaves the device · free, with nothing to buy.

### Claims that cannot truthfully be made

- **Anything with "AI" in it.** The only shipped provider is `TemplateFallbackProvider`:
  deterministic, offline, no model. D-024 and D-014 both forbid representing otherwise.
- **ADHD, executive function, focus disorders, anxiety, mental health, therapy, wellbeing.**
  `PRODUCT_SPEC.md` §1 hard boundary, and Apple 1.4.1 territory.
- **Grades, marks, academic results, "study smarter", productivity gains.** No evidence exists.
- **Sync, iCloud, backup, cross-device, web, Mac, iPad, Apple Watch.** None ship. iPhone only.
- **"Understands whatever you type."** The date parser recognises `today`, `tonight`,
  `tomorrow`, and weekday names, and deliberately refuses `march 14`, `in three days`,
  `next week`, `at 6`. Claiming general natural-language understanding is false.
- **NEXT+, premium, subscription, "more features coming".** Nothing is sold in 1.0 and Apple
  2.3.1(a) forbids promoting what the app does not offer.
- **"Fully accessible" / "VoiceOver ready".** Automated audits pass; real VoiceOver traversal has
  never been observed (B5). `TESTING.md` names this exact phrasing as forbidden.
- **Ratings, awards, user counts, testimonials, performance numbers.** None exist.

### Two claims that need a decision before they are printed

- **The widget.** It ships in the binary, its snapshot, staleness and deep-link rules are Tier 1
  and Tier 2 verified — but `containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil`
  in an unsigned build, so **no one has ever seen it display real content** (B1a). It becomes
  observable at TestFlight. **Recommendation: leave the widget out of every listing field until
  B1a and B5 are closed**, then add one line. None of the three descriptions below mentions it.
- **"NEXT does not use the internet at all."** `PRIVACY.md`'s draft says this. It is very nearly
  true and not exactly: NEXT's own code makes no network request — CI fails if any shipped source
  so much as names a networking API — but `NEXTApp` constructs a `StoreKitTransactionListener` at
  launch, and whether Apple's out-of-process daemon contacts Apple is not NEXT's to observe.
  `RELEASE_CHECKLIST.md` already states the claim at the honest width. **All three descriptions
  below therefore say "makes no network requests of its own" and "nothing you write leaves your
  phone", both of which are exactly true.**

### The audience the evidence supports

Students roughly 16–22, late secondary through undergraduate (`PRODUCT_SPEC.md` §1). Nothing in
the product excludes anyone else, and no direction below claims a demographic the app enforces.

---

## 2. Apple's current requirements, verified 2026-08-12

Checked against Apple's own documentation today rather than from memory.

| Field | Limit / rule | Source |
|---|---|---|
| App Name | 2–30 characters, required | [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/) — "at least two characters and no more than 30 characters" |
| Subtitle | ≤ 30 characters, optional | same page — "This can't be longer than 30 characters" |
| Promotional Text | ≤ 170 characters, **editable without a new build** | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/platform-version-information/) |
| Description | ≤ 4000 characters, plain text, no HTML | same page |
| Keywords | **≤ 100 bytes**, comma-separated, each term longer than two characters | same page — "Up to 100 bytes of content" |
| Keywords hygiene | "Don't repeat any words included in your app name, subtitle, or category" | [App Store search](https://developer.apple.com/app-store/search/) |
| What is indexed | app name, subtitle, keywords, **and the primary and secondary category** | [App Store search](https://developer.apple.com/app-store/search/) |
| Categories | one primary (required) + one optional secondary; primary drives browse placement | [App Store Category Definitions](https://developer.apple.com/app-store/categories/) |
| Screenshots | 1–10 per display size; 6.9″ **1320 × 2868 is an accepted portrait size**; no alpha channel | [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/) |
| Screenshot content | "should show the app in use"; overlays allowed; must suit a 4+ rating | App Review [2.3.3](https://developer.apple.com/app-store/review/guidelines/), 2.3.8 |
| Support URL | required, must lead to real contact information | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/platform-version-information/) |
| Privacy Policy URL | required, **and 5.1.1(i) also requires a link inside the app** | [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) |
| Copyright | required — "the person or entity that owns the exclusive rights", preceded by the year | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/platform-version-information/) |
| App Tags | **not authored by the developer.** Derived from your metadata plus AI plus human curation; you may only deselect. US storefront only at present | [Manage app tags](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-tags/) |
| Metadata rules | no unverifiable product claims in the subtitle; no prices in name/subtitle/screenshots; no keyword packing; no promoting functionality the app lacks | App Review 2.3.1(a), 2.3.7, 2.3.8, 2.3.10 |

**The two facts that shape the fields below.**

1. **Category is indexed and the keyword field must not repeat it.** So "productivity" is never a
   keyword in any direction, and neither is anything already in the name or subtitle.
2. **Promotional text is editable at any time without a submission.** It is the only field that
   can be changed after release without a review cycle, so none of the three directions spends a
   load-bearing claim there.

**The approved six-frame set is already compliant**: six frames, within 1–10; 1320 × 2868, an
accepted 6.9″ size; PNG without alpha; every frame shows the app in use rather than a splash
screen; captions are text overlays, which 2.3.3 permits.

---

## 3. Why would anyone choose NEXT?

Answered from the product before any keyword was chosen:

> Because every other app hands you back your list. NEXT hands you one thing, tells you why it
> picked it, and has an answer for the two moments a list has no answer for — when you cannot
> start, and when you are already late.

Everything below is a different way of getting that sentence into somebody's head in the two
seconds a search result gets.

---

## 4. Three directions

All three lead with **Productivity** as primary category: it is the only accurate one under
Apple's definition — "apps that make a specific process or task more organized or efficient…
task management" — and 2.3.5 warns that an irrelevant category is grounds for rejection.
Manufacturing category variety for the sake of three distinct-looking proposals would be exactly
that. The differentiation lives in the name, subtitle, keyword field and description, which is
where Apple's search algorithm actually looks.

**Education is deliberately not proposed as a secondary**, including for direction 2, where it is
tempting. Apple defines Education as "an interactive learning experience on a specific skill or
subject". NEXT teaches nothing, and `PRODUCT_SPEC.md` §1 explicitly says it is not a tutoring
system. Utilities — "enable the user to solve a problem or complete a specific task" — is
defensible for all three.

---

### Direction 1 — *One thing at a time*

**Positioning thesis.** NEXT is defined by what it refuses to be. Every competitor's answer to
"too much to do" is a better list; NEXT's answer is one card and a reason. Sell the mechanism,
because the mechanism is the differentiator and it is instantly legible.

**Intended user and search intent.** Someone who already owns a to-do app, already knows what
they owe, and still is not starting. They search `todo`, `task list`, `focus`, `what to do next`,
`priority`. Broadest of the three; also the most contested.

| Field | Value | Length |
|---|---|---|
| App Name | `NEXT: One Thing at a Time` | 25 / 30 |
| Subtitle | `Stop deciding. Start doing.` | 27 / 30 |
| Promotional Text | `No account, no sign-up, and no internet needed. Everything you write stays on your phone, and everything NEXT does is free.` | 123 / 170 |
| Keywords | `todo,task list,homework,assignment,deadline,study,revision,student,procrastination,overwhelmed,focus` | 100 / 100 bytes |
| Primary category | Productivity | |
| Secondary category | Utilities | |
| Description | 2143 / 4000 characters — in `scripts/validate-store-metadata.py` | |

**Description** (full text lives in the validator so it cannot drift from what was measured):
opens *"You have too much to do and no idea where to start. NEXT gives you one thing."*, then six
headed blocks — one card not a list · it tells you why · when you are stuck say so · when the
whole thing no longer fits · then it gets out of the way · nothing leaves your phone.

**How the six approved frames support it.** Almost perfectly, because the set was built to this
story. Frame 1 is the mess going in; frame 2 is the one card coming out *with its reason* — and
Apple shows the first one to three images in search results, so those two carry the thesis at
thumbnail size on their own. Frame 3 proves the choice is a *first move*, not a project. Frame 4
is "gets out of the way". Frames 5 and 6 are the two states a list cannot handle.

**Strengths.** The name explains the product without an adjective. The subtitle is a mechanism,
not a promise, so nothing in it is unverifiable under 2.3.7. It survives the app growing beyond
students. It matches the locked captions in voice almost exactly.

**Weaknesses.** `one thing at a time` is not a phrase anybody searches, so the name does almost no
discovery work and the entire keyword budget has to carry it. Competing for `todo` and `focus`
against enormous incumbents is the losing half of Apple's own stated trade-off between popular
and less common terms. And "one thing at a time" reads, at a glance, like a mindfulness app.

**Deliberately excluded.** AI · ADHD and every clinical adjacency · study outcomes · the widget
(B1a) · sync · anything about NEXT+.

---

### Direction 2 — *Homework and deadlines*

**Positioning thesis.** Stop selling a mechanism to everyone and sell a situation to one person:
six things due, a reading list not opened, an essay not started. NEXT is what you open on a
Sunday night. The audience `PRODUCT_SPEC.md` names is the audience the listing names.

**Intended user and search intent.** A student searching for the thing, not for a solution:
`homework`, `assignment`, `coursework`, `revision`, `study planner`, `exam`, `deadline`. Lower
volume than direction 1 and dramatically less contested, and the intent is much closer to the
moment NEXT is actually useful.

| Field | Value | Length |
|---|---|---|
| App Name | `NEXT: Homework & Deadlines` | 26 / 30 |
| Subtitle | `Six things due? Start one.` | 26 / 30 |
| Promotional Text | `Term has started. Put the whole reading list in, and NEXT will tell you which part of it to do first.` | 101 / 170 |
| Keywords | `study,revision,assignment,coursework,exam,essay,student,college,todo,task,procrastination,planner` | 97 / 100 bytes |
| Primary category | Productivity | |
| Secondary category | Utilities | |
| Description | 1907 / 4000 characters | |

**Description.** Opens on the situation rather than the product — *"Six things due this week. A
reading list you have not opened. An essay you have been not-starting for four days."* — then a
plain bulleted "what it actually does", the stuck paths written as coursework, the
too-late-to-do-it-properly section, and "no streaks, no guilt, no account".

**How the six approved frames support it.** Better than direction 1 in one specific place: frame
1's brain dump *is* a coursework dump, and this description has already told the reader that
before they look at it. Frames 5 and 6 stop being abstract product states and become the essay
and the missed deadline. The risk is frames 2–4, whose seeded content is a history essay — good,
but the listing now promises a homework app and three of six frames must carry it.

**Strengths.** The name contains two terms real people type, so the name does discovery work the
keyword field then does not have to repeat. `homework` and `coursework` are winnable in a way
`todo` is not. The subtitle is a scene, and scenes convert. Strongest match to the documented
audience, which means the listing and the product will not drift apart.

**Weaknesses.** It narrows a product that is not actually narrow — a graduate, a career-changer or
anyone with a job bounces off "Homework". It puts NEXT into the crowded student-planner shelf,
where every competitor promises scheduling and timetables and NEXT does none of it, so some
arrivals will be disappointed by the *absence* of a calendar. And it makes the app harder to
reposition later without changing the name, which is a searchable asset.

**Deliberately excluded.** Timetable, calendar and class-schedule language (NEXT does none of it,
and 2.3.1(a) makes promoting it removable) · grades and results · Education as a category · AI ·
ADHD · the widget.

---

### Direction 3 — *For when you cannot start*

**Positioning thesis.** Lead with the failure state. Knowing what to do is not the problem;
starting is. Rescue and Minimum Win — the two things nothing else on the shelf has — become the
headline instead of the third feature, and the ranking engine becomes support for them.

**Intended user and search intent.** Someone searching for their symptom rather than a tool:
`procrastination`, `overwhelmed`, `can't start`, `motivation`. Lower volume again, highest intent
of the three, and by far the strongest emotional hook — which is also its risk.

| Field | Value | Length |
|---|---|---|
| App Name | `NEXT: When You're Stuck` | 23 / 30 |
| Subtitle | `Too much to do? Do one thing.` | 29 / 30 |
| Promotional Text | `Free, offline, and no account. If you have opened five apps today and still not started anything, this is the one to try.` | 121 / 170 |
| Keywords | `procrastination,overwhelmed,homework,assignment,deadline,study,student,focus,todo,task list,planner` | 99 / 100 bytes |
| Primary category | Productivity | |
| Secondary category | Utilities | |
| Description | 2011 / 4000 characters | |

**Description.** Opens *"Knowing what you have to do is not the problem. Starting is."*, then
"I'm stuck is the main feature" with all four paths written out as the user would say them,
then the reason-on-the-card, then "it never tells you off", then "private by construction".

**How the six approved frames support it.** This is the only direction where **frame 5 is the
hero**, and it is the frame no competitor has. The set reads: here is your mess (1), here is the
one thing (2), here is the *first move* not the project (3) — which is the product's actual answer
to "I can't start" — the app leaves (4), and then the two frames that are the whole thesis:
stuck (5) and late (6). Frame 3's caption *Not the project. The first move.* is already written in
this direction's voice.

**Strengths.** It is the only one of the three that names the moment the app is genuinely unique
in. `procrastination` is a real search term with real volume that no incumbent to-do app owns.
The copy has somewhere to go that the others do not: it can describe Rescue in detail, which is
the most convincing thing NEXT has and the hardest to convey in a screenshot.

**Weaknesses — and one is serious.** Leading on "stuck", "overwhelmed" and "can't start" walks
straight up to the line `PRODUCT_SPEC.md` §1 draws around clinical territory, and the audience it
attracts will arrive with expectations the app cannot and must not meet. Holding that line is a
permanent editorial cost on every future update. Second, `NEXT: When You're Stuck` describes a
*feeling*, not a category, so a shopper who is not currently stuck has no reason to tap. Third,
the apostrophe in the name is a small ongoing nuisance in a searchable field.

**Deliberately excluded.** ADHD, executive dysfunction, focus disorder, anxiety, burnout, "brain
fog", and every other clinical or quasi-clinical term — the whole reason this direction is the
riskiest is that they would fit its voice perfectly and every one of them is forbidden · "beat
procrastination" and similar outcome promises, which are unverifiable claims under 2.3.7 ·
motivation-app framing, which contradicts P5 (no productivity morality) · the widget.

---

## 5. Recommendation

**Direction 2 — *Homework and deadlines*.**

Against the five criteria, in the order they actually bite:

- **Truthfulness.** All three are truthful; 2 is the *safest* of the three. Its claims are
  situational ("six things due") rather than psychological, so it has no standing temptation
  toward the clinical language §1 forbids. Direction 3 is truthful today and needs discipline
  to stay truthful for ever.
- **Immediate comprehension.** `NEXT: Homework & Deadlines` / `Six things due? Start one.` is
  understood with no inference at all. Direction 1's name requires a beat, and can be misread as
  mindfulness. Direction 3's name tells you a feeling, not a function.
- **Differentiation.** Weakest on paper — the name sounds like a planner — and rescued by the
  screenshots and the first description line, which sell the opposite of a planner. Direction 3
  differentiates best; direction 1 differentiates on a mechanism nobody searches for.
- **Search discoverability.** Decisively 2. `homework`, `coursework`, `assignment`, `revision`,
  `exam` are terms a new app with no ratings can genuinely rank for. Apple's own guidance frames
  this as the trade-off — popular functional terms drive traffic but are highly competitive,
  "especially if you are a newer or smaller app", and NEXT is the newest and smallest possible
  app. Direction 1 spends its whole budget competing for `todo` and `focus`, which it will lose.
- **Conversion.** Highest, because the intent is closest. Someone typing `homework` at 9pm on a
  Sunday is in exactly the state frame 1 depicts, and the first three frames answer them in
  order.

**The honest cost of choosing it:** the name narrows the product permanently, and a student who
arrives expecting a timetable will not find one. That is the trade I would make at launch, and it
is reversible in the direction that matters — name and subtitle are editable fields, and a listing
that has earned ranking on `homework` can broaden later, whereas a broad listing that never ranked
for anything has nothing to broaden from.

**If the owner would rather not narrow the product, take direction 3, not direction 1.** It is
better differentiated, better matched to the locked captions, and its weaknesses are editorial
discipline — which this project has demonstrably got. Direction 1 is the safest-sounding and the
weakest: it competes where NEXT cannot win, on a phrase nobody types.

**One hybrid worth naming rather than sneaking in.** Direction 2's name and keyword field with
direction 3's description opening is legal, coherent, and would probably outperform either — but
it is a fourth option, not a variation, and choosing it should be deliberate rather than a
merge that happened while nobody was looking.

---

## 6. OWNER INPUT REQUIRED

Nothing below can be derived from the repository, and none of it has been guessed.

1. **Support URL.** Required, and Apple requires it to lead to real contact information (a legal
   address, an email address, or a telephone number). It is also the outstanding placeholder in
   `PRIVACY.md` and `RELEASE_GATED.md` B3.
2. **Privacy Policy URL.** Required. The *text* is drafted and current in `PRIVACY.md`; it has no
   public home. **And a second, separate obligation:** App Review 5.1.1(i) requires a link to the
   policy *inside the app, easily accessible*. Settings has a Privacy section that states the
   position in prose but contains **no link**. That is a listing-blocking gap in the app, and it
   is recorded here rather than fixed, because today's task is not to modify the app and because
   there is no URL to link to yet.
3. **Copyright holder.** Required field: a person or entity name, with the year. No company
   identity exists in this repository and one has not been invented.
4. ~~**Primary storefront language.**~~ **Decided 2026-08-12: English (U.S.) — D-036.**
   `RELEASE_GATED.md` B3 step 1 is corrected in place and points at the entry, so the UK
   assumption cannot silently return. §9 lists every place the old register had leaked into the
   copy, and the check that the six approved captions needed no change at all.
5. **`adhd` as a keyword.** `PRODUCT_SPEC.md` §15's draft keyword field includes it, arguing it is
   a search term rather than a claim. **It is excluded from all three fields above**, for two
   reasons: 2.3.7 treats irrelevant keyword terms as grounds for modification or rejection, and an
   app that makes no ADHD claim anywhere is, by its own §1, not an ADHD app. Reinstating it is a
   deliberate owner call with a stated risk, not a default.
6. **Whether to mention the widget**, once B1a and B5 close.

---

## 7. Conflicts found while reconstructing state

Recorded rather than resolved, per the instruction to flag rather than silently choose.

**Conflicts 1 and 3 are resolved** — see §10 and D-037 for the recapture, and D-036 for the
storefront language. They are left in place rather than deleted, because how they were found is
worth more than the fact that they are closed.

1. ~~**RESOLVED (D-037).**~~ **The approved screenshot set's frame 6 was stale.** D-031 locks the set and says it is
   regenerated "only when a verified product change alters a screen it shows". The set was
   composited from run
   [31455519694](https://github.com/emoshansari-alt/NEXT/actions/runs/31455519694). D-030's fix
   (`ec11ddc`, after that run) changed `NextApp/Sources/Today/TodayView.swift` on exactly the
   state frame 6 captures: a task two days late now reads **`This is past its deadline.`** instead
   of `There is not enough time left to finish this.`, and **`What can I still do?` is now shown**
   where it previously vanished. Frame 6 therefore shows copy the app no longer draws. This is a
   **recapture, not a redesign** — same script, same grounds, same captions, same order, against
   new frames — and it is exactly the reopening condition D-031 anticipated. The caption
   *Behind? No lecture.* remains true of the new frame, and is arguably better supported by it.
   Frame 5 (Rescue) was checked and is **not** affected: `RescueView`'s change adds an
   initialiser and alters nothing the chooser draws.
2. **`PRODUCT_SPEC.md` §15 still calls D-030 open**, in the paragraph explaining frame 6's
   silence. D-030 was resolved on 2026-08-11. The frame's *silence* is still correct for a
   different reason — Rescue re-ranks and may offer a step from another task — but the stated
   reason is out of date.
3. ~~**RESOLVED (D-036).**~~ **The English (UK) / US register conflict** described in section 6,
   item 4. Settled as English (U.S.); §9's storefront table lists what it changed.

---

## 9. Evidence audit of the selected direction (2026-08-12)

Direction 2 was audited against the shipped product, the locked captions, Apple's metadata rules
and the newly-settled US storefront (**D-036**). **It survives as a positioning strategy** — the
thesis, the name and the subtitle are not challenged by anything below, and nothing here is a
change of taste. Seven findings, each with the evidence that produced it, and one non-finding
that matters.

### F1 — The fold spends its most valuable line on atmosphere · **fix proposed**

Apple: *"The first sentence of your description is the most important — this is what users can
read without having to tap to read more."* Direction 2 opens with three scene fragments and does
not state the mechanism until the second paragraph, which is below the fold. Direction 1 states it
in sentence one. 2R merges them: **"Six things due this week. NEXT gives you one of them — one
task, one action, and the reason it picked that one."** Situation and mechanism, both above the
fold, in 118 characters.

### F2 — "why that one and not the others" overstates the explanation · **fix proposed**

The engine explains why the winner won — `Due in 2 days.`, `Finishing this unblocks 3 other
tasks.`, `Nothing else is more pressing right now.` — and never compares it against the field.
`ExplanationReason` has seven cases and none of them is comparative. 2R says **"the reason it
picked that one"**.

### F3 — "separate tasks with deadlines" implies date understanding NEXT does not have · **fix proposed**

`DatePhraseParser` recognises `today`, `tonight`, `tomorrow`, and weekday names, and *deliberately*
refuses `march 14`, `13/03/2026`, `in three days`, `next week` and `at 6`. The bullet as written
reads as general extraction. 2R replaces it with the honest and more distinctive claim: **"Reads
the dates it recognizes, and asks instead of guessing when it does not"** — which is the actual
design position, that a wrong deadline is worse than a missing one.

### F4 — "a first step you can do in five minutes" is a duration promise the shrinker does not make · **fix proposed**

The five-minute figure is real but it belongs to one path. `StepShrinker`'s generic fallback is
*"Spend five minutes on that one thing."* and `RescueStrategy.dontWantTo` bounds the deal at five
minutes; the ordinary shrink to a physical first step carries no duration at all. 2R moves the
number to where it is literally true — the *I just don't want to* line — and the bullet becomes
**"Breaks a task you are avoiding down to one physical first step"**.

### F5 — the Minimum Win sentence is garbled, and reads toward the academic-integrity line · **fix proposed**

> "…gets a smaller version that is still worth handing in the work for…"

It is hard to parse, and the reading a tired shopper takes from it — hand in the smaller version —
is the one `PRODUCT_SPEC.md` §4.12 explicitly forbids Minimum Win from encouraging. Minimum Win is
about the highest-value *progress*, not about what gets submitted. 2R: **"…gets a smaller version
that is still worth doing — outline, then introduction, then first section — and a time to come
back and reassess."**

### F6 — one claim is made twice, and one Rescue path is missing · **fix proposed**

"reads it into separate tasks" appears in paragraph two and again as the first bullet; "why it
picked it" appears in both as well. Separately, the description walks three of Rescue's four paths
and silently drops *I just don't want to* — the one with no equivalent anywhere else on the shelf.
2R removes both repetitions and sets all four paths out as a list, which is also where F4's five
minutes now lives.

### F7 — two keywords are working against the product · **fix proposed**

- **`revision`** is British for studying for exams; on a US storefront (**D-036**) it reads as
  editing a draft, and buys the wrong intent with bytes that are not spare.
- **`planner`** targets a category `PRODUCT_SPEC.md` §1 explicitly refuses — "not a planner
  suite". It buys arrivals who want a timetable and will not find one, which is the mechanism
  behind direction 2's one real weakness rather than a mitigation of it.

2R swaps them for `overwhelmed` (on-message, non-clinical, and what Rescue is actually for) and
`school`. 99 / 100 bytes.

### The non-finding: `Homework & Deadlines` does not narrow NEXT harmfully

It narrows it, and the narrowing is honest — NEXT does both things named. The risk is not false
advertising but adjacency: "Deadlines" can read as a countdown app and "Homework" as a planner,
and both are categories NEXT refuses. That risk is already answered where it lands, by the first
description line and by frames 1 and 2, which sell the opposite of a list. **Recommendation: keep
the name and subtitle exactly as selected.** F7's removal of `planner` strengthens this rather
than weakening it.

### What the audit found nothing to change

- **Generic productivity language:** none. No instance of any banned pattern; the word
  "productivity" does not appear in any field.
- **Awkward ASO phrasing in human-readable copy:** none. The keyword field is machine-read;
  nothing in the description is written for the algorithm.
- **Accidental implications:** checked one by one and all clear. **AI** — nothing implies a model,
  and F3's fix makes the deterministic behaviour an explicit selling point. **Cloud** — "makes no
  network requests of its own" is stated. **Accounts** — "no sign-up, no email address". **Therapy
  or ADHD** — "an essay you have been not-starting for four days" is behavioural, not clinical; no
  condition is named anywhere; `adhd` is not in the keyword field. **Educational outcomes** — no
  grade, mark, result or performance claim exists. **In-app purchases** — nothing is mentioned,
  which is correct, because there are none.
- **Listing against the six frames:** reinforcing throughout, no contradiction. Frame 1 ↔ "put it
  all in"; frame 2 ↔ "one card"; frame 3 ↔ "the smallest physical action"; frame 5 ↔ "say what is
  in the way", which is nearly the caption verbatim; frame 6 ↔ "says so, without a lecture".
  Frame 4's *Then it gets out of the way* was the one beat the description did not answer, so 2R's
  Focus bullet now ends **"then leaves you alone"**.

### Storefront language (**D-036** — English (U.S.))

| Where | Current | Status |
|---|---|---|
| Description | `For sixth form, college and university.` | **UK-only term.** 2R: `For high school and college.` — which is also exactly `PRODUCT_SPEC.md` §1's "late high school through undergraduate" |
| Description | `for ever` | UK two-word form. 2R: `forever` |
| Description | `Haven't got the time` / `how long you have got` | British idiom. 2R: `I don't have the time` / `say how much you have` |
| Promotional text | `Term has started.` | Reads as UK academic. 2R: `New semester.` |
| Keywords | `revision` | F7 above |
| **Screenshot captions** | all six | **No inconsistency. Nothing changed.** Every caption is US-neutral; D-031 had already moved the one British phrase out of the set |
| **In-app copy** | all user-facing strings | **No inconsistency found.** Scanned for the usual markers — `colour`, `organis*`, `personalis*`, `behaviour`, `whilst`, `for ever`, `practise`. The only hit is `"practise"` inside `WorkKind`'s keyword table, which is an input token NEXT *matches on*, listed beside `"practice"`, and is never displayed. British spelling in identifiers and documentation (`Monetisation`) is internal and out of scope |

### Both versions are measured, not eyeballed

`scripts/validate-store-metadata.py` holds direction 2 and 2R side by side, so the audit's proposal
cannot quietly break a limit:

| | Name | Subtitle | Promotional | Description | Keywords |
|---|---|---|---|---|---|
| 2 | 26 / 30 | 26 / 30 | 101 / 170 | 1907 / 4000 | 97 / 100 bytes |
| **2R** | **26 / 30** | **26 / 30** | **97 / 170** | **2058 / 4000** | **99 / 100 bytes** |

---

## 10. Frame 6, recaptured (D-037)

Done, verified, and frames 1–5 are byte-for-byte what they were. The full reasoning is in
**D-037**; the short version:

- **The condition was D-031's own.** D-030's fix altered the screen frame 6 shows.
- **A whole-set recapture was measured and rejected.** Frames 02–05 came back byte-identical
  across the two runs, so the capture is reproducible — but frame 01 did not, because iOS's
  QuickType bar offered three predictive suggestions in one run and none in the other. That is
  Apple's keyboard, not NEXT, and adopting it would have changed a locked frame for a reason
  outside the product.
- **So only frame 6 was taken from the new run**, and the substitution is expressed in the
  command rather than in a folder assembled by hand:

  ```bash
  python scripts/compose-store-screenshots.py approved/screenshots new/screenshots#06-late out
  ```

- **Verified by reading the frame**, not the diff: the card now carries `This is past its
  deadline.` and the `What can I still do?` affordance is present below START. The old frame had
  `There is not enough time left to finish this.` and no affordance.
- **The caption is unchanged.** `Behind? No lecture.` was true of the old frame and is better
  evidenced by the new one. Its contrast on `#0E7490` is re-asserted at 5.4:1 before the file is
  written.
- Composing from the approved run alone and from the mix yields **identical SHA-256s for frames
  01–05**, and a frame 06 differing only inside the screen area, below the caption band.

---

## 11. What happens after the selection

1. Replace `PRODUCT_SPEC.md` §15's "Listing copy" block with the approved copy, and record the
   choice in `DECISIONS.md` as the entry that closes D-024's checkpoint for wording.
2. Reduce `scripts/validate-store-metadata.py` to the single approved listing and wire it into the
   guardrails job, so the limits stay enforced rather than checked once. Delete the losing
   directions from this file rather than leaving them to be mistaken for live options.
3. ~~Recapture frame 6~~ — **done, D-037.** Frames 1–5 preserved byte-for-byte.
4. Fill the owner-supplied fields in section 6, and add the in-app privacy-policy link, before
   `RELEASE_GATED.md` B3 step 5 can be executed.
