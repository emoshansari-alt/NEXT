# NEXT — Session Log

Newest entry first. This file is the project's memory. A new agent should be able to read this
plus `PRODUCT_SPEC.md`, `ARCHITECTURE.md` and `DECISIONS.md` and resume with no chat history.

---

## 2026-08-09 — Session 10: the release-blocking gaps, and four decisions taken rather than deferred

**Objective.** Work down the remaining 1.0 list autonomously: relaunch persistence, daily
replanning, the notification deep link, the accessibility audit, and the last stubbed factor.

### Result

**Tier 1: 549 tests / 100 suites. Tier 2: 103 unit / 24 suites (2 known issues) + 34 UI tests.**
Green — run [31296600849](https://github.com/emoshansari-alt/NEXT/actions/runs/31296600849).

Four decisions were made and written down rather than escalated — D-018, D-020, D-021, D-022.
Three of them closed questions that had been carried for several sessions.

### Relaunch persistence — the oldest gap, closed

Carried since Session 3. The suite structurally could not answer it: `-ui-testing` swaps in a
fresh in-memory container per launch, so "relaunch and verify" passed regardless of what the
persistence layer did.

`-ui-store-name` now puts a real SwiftData store on disk in a throwaway location, with
`-ui-reset-store` clearing it on a test's first launch only. The full cycle runs: create,
terminate, relaunch, verify, edit, terminate, relaunch, verify the edit, complete, terminate,
relaunch, verify it is filed rather than deleted.

**Three of its assertions passed for the wrong reason first.** An Everything row is a `Button`
carrying its own accessibility label, so the title inside it is not a separate element — a lesson
already in `TESTING.md` that I did not apply to my own test. Searching `staticTexts` for the title
matched *Today*, behind the sheet, showing the same title. It only came apart when the task was
completed and Today fell back to its empty state. **The mutation-testing rule applies to UI tests
too:** a green assertion that never looked at the screen it names is exactly what that rule exists
to catch.

### Daily replanning — the Session 1 question, answered (D-020)

§4.13 asks that a new day reassess what matters now. The thing standing in the way was the open
question Session 1 recorded and explicitly said not to resolve silently: overdue contributed a
flat full weight with no decay, so a task three months late scored what it scored an hour late and
pinned to Today permanently.

That is a defect against P4 and P5, not a tuning preference — a screen showing the same
unachievable thing every morning for a term is punishment however neutrally worded, and an app
whose one recommendation never changes has stopped recommending. Both deadline factors now fade
across fourteen days to a floor of a quarter, through **one shared curve**, because lateness is a
single idea and two curves that could drift apart would make behaviour past a deadline impossible
to reason about. The floor is not zero: the work is still outstanding.

### The notification deep link — a half-built feature finished

Reminders have carried a task identifier since Session 7 and nothing ever read it back, so tapping
"Chemistry worksheet is due tomorrow" opened the app and showed whatever Today happened to be
recommending. `ScheduledReminder` now owns the payload key, the payload and the destination, so
the scheduler and the handler cannot drift; `DeepLinkInbox` parks the tap because a cold launch
from the lock screen delivers before Today exists.

Notification **actions** were decided out of 1.0: §8 specifies categories, contextual permission
and real controls, and does not ask for them.

### The accessibility audit — run for the first time, and split honestly (D-021)

P8 calls an accessibility defect in a core flow a release blocker, and nothing had ever checked.
The first run failed on all ten core screens.

The console gives the fault but not the control, and the detail lives in an xcresult bundle that
cannot be opened from Windows — so the audit was changed to report each issue's identifier, label
and frame. One diagnostic round produced the whole list, and it was **not** what I predicted.

Fixed, because they are NEXT's: **eight controls below 44 × 44**, every one a plain text button
whose hit area was a line of text tall — "Everything" measured 73 × 18. They read correctly as
quiet secondary actions and were genuinely hard to hit one-handed, and "I'm stuck" is used
precisely when someone is already having a bad time. Plus **three clipped labels**, including
Rescue's own question, which at larger type sizes was cut off — on that screen the question
becoming unreadable is the whole screen failing.

Not fixed: contrast and Dynamic Type are overwhelmingly the system tint on `.bordered` buttons,
the standard `.secondary` colour, and navigation-bar buttons SwiftUI does not scale at all.
Choosing a palette that clears 4.5:1 in both appearances is Phase 12. They sit under a **strict**
`XCTExpectFailure`, so the day the palette lands the test fails for *not* failing and whoever did
that work is told to come and enforce it.

### `friction` — the last stub, decided (D-022)

Every candidate signal is already counted or actively wrong. A missing first step is
`startability`; recent refusals are `rejectionPenalty`; a refusal's *reason* would outlive the
cooldown and permanently demote a task on one tap, which is the shape D-020 had just been written
to remove. The most tempting signal is the worst: "started and still outstanding" describes a task
in progress exactly as well as an abandoned one, so it would push the user off work they began a
minute ago.

It stays zero, present in every breakdown, with tests sweeping the shapes that might plausibly
have earned a penalty — so implementing it later means deleting tests that say why it was zero.

### The audit caught a defect I introduced while fixing another one

Worth recording plainly. Giving Capture's "just save it as one task" button room to wrap — the fix
for it clipping at the default size — made the bottom action bar taller. That bar sits above the
keyboard on the one screen the user types on, and at accessibility XXXL the save button stopped
being reachable at all. `testTodaySurvivesTheLargestAccessibilitySize` had passed in the audit's
first run and failed in the next.

The 52-point floor under the primary button was the dead weight: a sensible target when the label
is small, and pure padding once the label is already taller than it. It is now dropped at
accessibility sizes.

Two things follow. A layout fix at one type size can break another, and only a test that actually
runs at that size will say so. And the audit earned its keep inside a single session — not by
finding the original defects, but by catching the one introduced while repairing them.

### Known limitations

- Contrast and Dynamic Type do not pass; tracked, not silently excluded (D-021).
- Notification **delivery** has still never been observed — B5.
- No real purchase has ever been exercised (B4a); the widget's content is unverifiable (B1a).
- The Rescue ladder does not advance between visits: `stepsAlreadyRevealed` is caller-held and
  every caller passes zero, so asking twice gives the same first rung. Related to D-018.
- A user who records a large next action and then says "It's too much" gets their own sentence
  back — `StepShrinker` puts a recorded next action first on purpose.

### Exact next action

**Phase 12 — visual design.** It is now the largest remaining block and it owns three checklist
items at once: the palette (which makes the D-021 expectation fail and get removed), the app icon,
and typography. Per **D-014** the order is Claude's own design tooling first, Higgsfield only for
what that cannot do; check whether a `/design` skill exists before assuming it does not.

Then: the schema-migration round-trip test, which is the last unticked engineering item that needs
no device and no palette.

---

## 2026-08-09 — Session 9: StoreKit, and three flows that were built but unreachable

**Objective.** Phase 10 (StoreKit), then close the three core-product gaps the last three
sessions had been carrying.

### Result

**Tier 1: 531 tests / 97 suites. Tier 2: 97 unit / 22 suites (2 known issues) + 20 UI tests.**
Green — run [31290672207](https://github.com/emoshansari-alt/NEXT/actions/runs/31290672207).

Two Apple facilities were measured and both turned out to need signing. Neither was assumed.

### Part one — monetisation, gating nothing

The whole stack exists: `NextKit/Monetisation/` owns every rule — tier resolution, entitlement
records and their resolver, the capability gate, the product catalogue, the `PurchaseService`
protocol — and `NextApp/Monetisation/` owns the one file that imports StoreKit, the transaction
listener, and the paywall.

**Nothing is behind it** (D-015, owner's decision). `FeatureGate.oneDotZero` lists every
capability NEXT has as free, and a tripwire test fails if that changes without the NEXT+ boundary
decision being made first. Taking a working feature away to manufacture a paid tier is not
something this product does.

**The paywall ships complete and unreachable.** NEXT+ unlocks nothing, so selling it would be
selling nothing. It is finished, Tier 2 verified behind the `-storekit-testing` launch argument,
and a UI test asserts a normal build has no way to it. `RELEASE_CHECKLIST.md` blocks release on
deciding the boundary or stripping the screen.

Three entitlement rules that could each have gone the other way, and are pinned by mutation-tested
cases: a declined card keeps access while Apple retries it, **bounded** so a stuck flag cannot
become a free subscription; revocation is honoured **per receipt**, so refunding a subscription
cannot take away a lifetime purchase; and `.unknown` is not `.free`, so a subscriber whose
entitlement has not loaded is never shown a paywall for what they already own.

### The StoreKit answer, and a pattern worth carrying

**Local StoreKit testing does not work in an unsigned Simulator build.** Both documented routes
were measured. `SKTestSession` with the configuration in the test bundle: the file is found — a
diagnostic run confirmed the exact path — the session is created, and then every operation fails
with `SKInternalErrorDomain` Code 3, *including `clearTransactions()`*. The scheme's own StoreKit
configuration, verified by CI to actually be present in the generated scheme: same empty
catalogue.

An error deleting transactions cannot be caused by a file it never reads. That one detail is what
turned a guess into a conclusion, and it is why the diagnostic was worth a CI round.

Recorded as `RELEASE_GATED.md` B4a and as **D-017, which corrects D-001**: local StoreKit belongs
to Tier 3. Two of the three capabilities D-001 expected to come free at Tier 2 turned out to need
signing, so the entry names the pattern rather than just the instance — **an entitlement-scoped
Apple facility should be assumed Tier 3 until measured.**

### Part two — the three flows

Each was already correct in `NextKit` and either unreachable or dropped in the app.

**A task cannot describe a smaller version of itself**, which is why passing `TaskItem` to Focus
was the root defect: Rescue would shrink "History essay" to "Open the assignment instructions.",
the user would tap "Do that", and Focus would open on the essay. `FocusTarget` carries the task,
the action, its origin, and whether it is reduced.

Two propagation rules are load-bearing, and both are the kind of defect that renders perfectly:

- **The task comes from the response, not the screen.** Rescue's "I don't have enough time" path
  re-ranks and can legitimately answer about a *different* task.
- **A withheld title stays withheld.** "It's too much" does not name the task on purpose; Focus
  re-deriving it from the task would undo the only thing that path does.

**A reduced action never completes its task** (D-018). The button reads "Done with this step" and
does that. Whether a finished step should also become a child task is left open rather than
guessed at — recording a step later is additive, whereas wrongly completing a task destroys work.

**Minimum Win finally has a caller.** Offered on Today when the recommendation's own
`deadlineFeasibility` is unreachable, so the ladder cannot contradict the screen that led to it,
and never offered for work that comfortably fits.

**"I'm stuck" is reachable from inside Focus** (`PRODUCT_SPEC.md` §4.9), and the smaller step
replaces the action in place. The timer returns to the chooser, because a length chosen for the
bigger piece of work does not apply to this one.

### What the tests caught that reasoning did not

A Tier 2 test failed asserting a rescued step differs from what Today was showing. It was **the
test that was wrong**, not the code: the fixture recorded "Write the whole thing." as a next
action, and `StepShrinker` deliberately puts a recorded next action at the head of the ladder —
the user wrote it, and nothing inferred from a keyword read of a title beats that.

The real behaviour is now tested and named rather than hidden behind a friendlier fixture: **a
user who records a large next action and then says "It's too much" gets their own sentence back.**
Overriding it would mean NEXT deciding a user's own words are wrong on the strength of a template.
That is a product decision, not a bug fix, and there is no evidence yet about which way it should
go.

One prediction was also wrong in the other direction: `.fullScreenCover(item:)` was expected not
to refresh when the item changes but keeps its identity. It does refresh — the loop UI test
passes. Measuring beat guessing again.

### Known limitations

- **Persistence across relaunch is still untested.** The UI target gets a fresh in-memory store
  per launch. This is now the oldest outstanding gap in `TESTING.md`.
- Notification **delivery** has still never been observed — only the plan is verified.
- No real purchase has ever been exercised (B4a); the widget's content is still unverifiable (B1a).
- No notification actions, and no deep link from a notification.
- Daily replanning has no day-boundary behaviour.
- An empty-but-successful entitlement set reads as the free tier (**D-019**) — harmless while
  nothing is gated, and a prerequisite of the boundary decision rather than a follow-up to it.
- `friction` is still an explicit zero.

### Exact next action

**Relaunch persistence at Tier 2.** It is the oldest gap, it is release-blocking in
`RELEASE_CHECKLIST.md`, and it needs a different arrangement than the suite currently has: the UI
target deliberately swaps in an in-memory store, so the create → terminate → relaunch → verify
cycle needs a launch mode that keeps a *real* store in a throwaway location, cleaned between
runs rather than replaced per launch.

Then, in order: **daily replanning** across a day boundary (§4.13, the last unbuilt behaviour in
the 1.0 list), **notification actions and the notification deep link**, and the **accessibility
audit** — which is release-blocking and has never been run.

Phase 12 visual assets follow **D-014**: Claude design tooling first, Higgsfield as fallback.

---

## 2026-08-09 — Session 8: widget, deep links, and the App Group answer

**Objective.** Build the widget, and find out whether an App Group actually works unsigned
rather than assuming either way.

### Result

**Tier 1: 481 tests / 89 suites. Tier 2: 66 unit (1 known issue) + 13 UI tests.** Green —
run [31286116920](https://github.com/emoshansari-alt/NEXT/actions/runs/31286116920).

### The App Group experiment, and its answer

The widget needs to read what the app writes, which needs a shared container, which needs an
App Group entitlement. Whether that works in an unsigned Simulator build was genuinely unknown,
so rather than guess, a Tier 2 test **asserted** the container resolves.

**It does not.** `containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil` —
App Groups are *provisioned* entitlements and declaring one in `project.yml` is not enough.
Evidence: run [31285133615](https://github.com/emoshansari-alt/NEXT/actions/runs/31285133615).

Recorded as `RELEASE_GATED.md` **B1a** with what still works without it. The widget compiles,
installs and renders its placeholder; the app is entirely unaffected. Snapshot construction,
staleness, JSON round-tripping and deep-link parsing are all verified. Only the app-to-widget
handoff is gated.

The tests now assert what is true in *each* world: with a container the round trip must work
(marked `withKnownIssue`, so it starts running for free the day signing exists); without one the
degradation must be silent — writes are no-ops, reads are `nil`, nothing throws. That second
branch is the one running today, and it is the one that matters: a widget that cannot update
must never become a problem the user sees.

### Design worth keeping

The widget never opens the task store. Extensions run under a hard memory limit and are woken
at unpredictable moments, so standing up SwiftData and a migration plan to render two lines
would be slow and fragile. The app writes a few hundred bytes of JSON instead — which also
confined the entitlement's blast radius to the widget alone.

Snapshots carry rendered strings and the publisher reads the same `UnavailabilityCopy` the Today
screen does; two surfaces describing one state differently is how a user learns to trust
neither. A snapshot goes stale after a day, but one dated in the *future* is deliberately not
stale — reachable from a clock change, and blanking the widget for a reason the user cannot see
or fix is worse than being slightly off.

`DeepLink` lives in `NextKit` so the widget, notifications and the app parse links identically.
Unrecognised links are rejected rather than guessed at; a link to a deleted task leaves the user
on Today, which is reachable in normal use.

### A real flake, fixed properly

`typeText` returns before SwiftUI has processed every keystroke, and on a loaded runner the
assertion read a half-typed `"Email Pr"`. The same test had passed in earlier runs — which is
what made it worth fixing rather than re-running. Now a polled `XCTNSPredicateExpectation`.

### Known limitations

- **The widget's content is unverifiable until signing.** It renders a placeholder in CI.
- Notification **delivery** has still never been observed — only the plan is verified.
- No notification *actions* (complete/snooze from the banner).
- Minimum Win has a tested planner and **no caller in the UI**.
- Rescue's "Do that" opens Focus on the parent task, not the shrunken step.
- "I'm stuck" is not reachable from inside Focus.
- No StoreKit or paywall. `friction` is still an explicit zero.

### Exact next action

**StoreKit (Phase 10)** — the last unbuilt area of the 1.0 scope. In order: a `.storekit`
configuration file, an entitlement model in `NextKit` (locally testable, mirroring how
`ReminderPlanner` works), a `PurchaseService` protocol so view models can be tested without
StoreKit, and the paywall — invoked only by intent, never at launch.

Note before starting: `.storekit` local testing is a scheme option, so check whether it can be
driven from `xcodebuild` in CI or whether it, like the App Group, turns out to be gated.

Then the smaller gaps: Minimum Win needs a caller, Rescue should carry its step into Focus, and
"I'm stuck" should be reachable from Focus.

---

## 2026-08-08 — Session 7: Settings, notification scheduling, consent switch

**Objective.** Build the last 1.0 surface that did not exist at all, and the notification
scheduling behind it.

### Result

**Tier 1: 468 tests / 85 suites. Tier 2: 55 unit + 13 UI tests.** Green on the first CI attempt
— run [31284277004](https://github.com/emoshansari-alt/NEXT/actions/runs/31284277004).

**All nine primary surfaces from `PRODUCT_SPEC.md` §4 now exist**: Onboarding, Today, Capture,
Capture Confirmation, Everything, Task Detail, Focus, Rescue, Settings.

### What was built

**`ReminderPlanner`** in `NextKit` — a pure function deciding what NEXT would ask iOS to
deliver, so every scheduling rule is checked at Tier 1 rather than by watching a device.

What it *refuses* to schedule is the substance:

- nothing for finished or filed work — a notification about a completed task is the clearest
  possible signal an app is not paying attention
- nothing for an overdue task — the user knows; daily replanning surfaces it in the app, and a
  push about it would be the app telling them off (P5)
- nothing whose moment has passed, since iOS delivers those immediately
- no daily reminder when nothing is outstanding, which is pure engagement bait

It caps at **64**, because that is what iOS holds before silently discarding the rest — so the
choice of what gets dropped is ours (the soonest survive) rather than the system's. Identifiers
are stable, so re-planning replaces rather than stacking duplicates. A test sweeps every
generated string for "miss you", "don't forget", "still", "behind", "hurry", and "!".

**Permission is requested when a reminder is switched on, never at launch.** Being asked to
allow notifications before writing down a single task is a request with no context. A refused
permission is stated plainly rather than left as a switch that silently does nothing. Sound and
badge are not requested at all — a badge counting outstanding work is exactly the low-grade
pressure this app exists to remove.

`TodayViewModel` reschedules after every write, so completing something cancels its reminder.

**The cloud-processing consent switch exists and defaults to off.** Nothing reads it yet — the
only provider is the offline template one, which sends nothing — and the Settings footer says
exactly that rather than implying a feature. It is built first so a cloud provider cannot be
added later without a consent gate already in front of it (`PRIVACY.md`).

Settings is reached from Everything, not Today. Today's job is to show one thing; a gear would
be a sixth control on a screen whose point is that there is nothing to choose between.

### Known limitations

- **Notification *delivery* has never been observed.** Simulator notification behaviour is not
  device behaviour, and no test asserts anything arrives. Only the plan is verified. Real
  delivery is `RELEASE_GATED.md` Gate B.
- Rescue's "Do that" still opens Focus on the parent task rather than the shrunken step.
- No notification *actions* (complete/snooze from the banner), no deep link from a notification.
- No widget, no StoreKit, no paywall.
- `friction` is still an explicit zero.
- No relaunch-persistence UI test — the UI target gets a fresh in-memory store per launch.

### Exact next action

1. **Widget** (Phase 9) — one timeline entry showing the current recommendation, with a deep
   link into the app. Requires an App Group so the widget can read the same store, which is the
   first piece of work that touches entitlements; check whether an App Group works unsigned in
   the Simulator before assuming it is release-gated.
2. **Notification deep link and actions** — tapping a reminder should open that task.
3. **StoreKit** (Phase 10) — `.storekit` configuration, entitlement model, paywall.
4. Rescue → Focus should carry the shrunken step through.

Phase 12 visual assets follow **D-014**: Claude design tooling first, Higgsfield as fallback.

---

## 2026-08-08 — Session 6: onboarding, the Focus timer, and Break it down

**Objective.** Finish the surfaces that make a coherent first run, and give the intelligence
layer its first real caller.

### Result

**Tier 1: 452 tests / 82 suites. Tier 2: 46 unit + 12 UI tests.** All green on the first CI
attempt — run [31279172396](https://github.com/emoshansari-alt/NEXT/actions/runs/31279172396).

### What was built

Two pieces of domain logic went into `NextKit` specifically so they could be tested locally
rather than through ten-minute CI rounds:

- **`FocusSession`** — a value type that *does not tick*. Elapsed time is arithmetic against
  whatever instant the caller asks about, so nothing runs, nothing needs cancelling, and a
  session survives the app being backgrounded or killed without bookkeeping. `remaining()`
  returns `nil` rather than zero when there is no timer, because zero renders as "0:00 left" —
  a different and untrue claim. `spokenRemaining()` exists because VoiceOver reading "23:30" as
  digits is close to useless and timer state must be accessible.
- **Decomposition → child tasks** — steps become real tasks linked by `parentID`, the shape
  `StepShrinker` and `MinimumWinPlanner` already read, so breaking a task down improves Rescue
  and Minimum Win too. **The parent then waits on its own steps** via `prerequisiteIDs`, so the
  engine recommends a step rather than the mountain. Without that, decomposing would make the
  screen *worse* — the parent competing with its own pieces. Written as one batch including the
  parent, because half a decomposition is exactly that failure.

App layer: **Onboarding** (three screens, asks for nothing, Skip always available — a UI test
asserts zero text fields so "just one small question" cannot creep in), the **Focus timer**
(length chosen before the clock starts; "Just start" sits alongside the presets as a normal
choice, not an opt-out), and **Break it down** in Task Detail.

### A compiler crash worth knowing about

`paused(at: at(5))` — a helper whose name matches an argument label, nested inside it — crashed
`swiftc` 6.3.3 on Windows with `compile command failed due to exception 3`, reporting no file
and no line. `swift build` passed; only the test target failed. Found by removing test files
one at a time. Recorded in `TESTING.md`; the helper is now `mark(_:)`.

### Known limitations

- **Rescue's "Do that" still opens Focus on the parent task**, not the shrunken step. The step
  is what the user was just shown, so this is not wrong, but Focus should display it.
- **No Settings screen** — so no notification controls and no cloud-AI consent switch, which
  `PRIVACY.md` promises before any task text leaves the device. Nothing sends anything today
  (the only provider is the offline template one), so nothing is currently misrepresented.
- No notifications, no widget, no StoreKit.
- `friction` is still an explicit zero.
- Still no relaunch-persistence UI test — the UI target gets a fresh in-memory store per launch.
- Onboarding illustrations are text-only. Phase 12 and **D-014** cover that.

### Exact next action

1. **Settings** — notification permission controls and the cloud-AI consent switch. It is the
   last surface in the 1.0 list that does not exist at all.
2. **Notifications** (Phase 9) — deadline reminders and the optional daily NEXT reminder, with
   permission requested contextually rather than at launch. Scheduling logic belongs in
   `NextKit` where it can be tested locally; only delivery needs the app.
3. **Rescue → Focus** should carry the shrunken step through.
4. **Widget** (Phase 9) and then StoreKit (Phase 10).

Phase 12 visual assets follow **D-014**: Claude design tooling first, Higgsfield as fallback.

---

## 2026-08-08 — Session 5: Everything, Task Detail, Rescue wired up

**Objective.** Close the repair hole — capture was a one-way door — and give the finished
Rescue module a way in.

### Result

**Tier 1: 426 tests / 77 suites. Tier 2: 46 unit + 10 UI tests.** All green —
run [31278176415](https://github.com/emoshansari-alt/NEXT/actions/runs/31278176415).

### What was built

- **`TaskSections`** in `NextKit` — the Everything screen's date bucketing, 16 Tier 1 tests.
  In the domain layer rather than the view because a calendar boundary is easy to get subtly
  wrong and impossible to check from a screenshot. A deadline earlier today is **Overdue**, not
  Today: filing it under Today would hide something already late.
- **Everything** — sections, swipe to complete/reopen/delete, push to detail. Deliberately not
  a second place to decide what to do; Today owns that, and duplicating it would put the user
  back in front of the whole list.
- **Task Detail** — edits held locally and written on save, so backing out of a half-typed
  title is not what gets stored. Blank titles refused. Deletion real, and says so.
- **Rescue UI** — the module was fully built and Tier 1 tested with no way to reach it. Now
  behind "I'm stuck", on its own line above the other secondary actions.
- **`TaskItem.notes`**, which `PRODUCT_SPEC.md` §4.8 required and the model lacked.
- **Archived is its own section** rather than hidden. A state with no way back is a trap.

### Four CI rounds, all mine, all Tier 2-only failures

The app layer cannot compile here, so these are only findable in CI:

1. **A sheet cannot be presented while another is dismissing.** Opening a task dismissed
   Everything and set the detail sheet in the same tick; the second was swallowed. Detail is
   now *pushed* onto Everything's own stack — the more natural shape anyway, since you come
   back to the list you were in.
2. A pushed detail must not carry its own `NavigationStack` or Close button.
3. **A `Form` renders rows lazily**, so the delete button below the fold genuinely did not
   exist. Scrolled to it.
4. Dumping `app.debugDescription` again narrowed round 3 in a single run.

### Known limitations

- **No onboarding.** The three screens from §4.1 do not exist; the app opens straight onto Today.
- **"Break it down" is not wired.** `IntelligenceProvider.decompose` exists and is tested, but
  nothing calls it — Task Detail has no button for it yet.
- Rescue's "Do that" opens Focus on the parent task rather than on the shrunken step. The step
  is what the user was just shown, so this is not wrong, but Focus should display it.
- No Focus timer, notifications, widget, StoreKit, or Settings.
- `friction` is still an explicit zero.
- Still no relaunch-persistence UI test — the UI target gets a fresh in-memory store per launch.

### Exact next action

1. **Onboarding** — three screens, no account, then straight into an empty Today. Persist
   completion in `UserDefaults`; it is the last surface standing between this and a coherent
   first run.
2. **"Break it down"** in Task Detail, calling `decompose` and writing the steps as child tasks
   via `parentID` — which is what `StepShrinker` and `MinimumWinPlanner` already read.
3. **Focus timer** (Phase 6) — presets 5/15/25/45/none, with timer state announced accessibly.
4. **Settings** — notification controls, and the cloud-AI consent switch `PRIVACY.md` promises.

Phase 12 visual assets follow **D-014**: Claude design tooling first, Higgsfield as fallback.

---

## 2026-08-08 — Session 4: capture — NEXT becomes usable by a real person

**Objective.** Phase 5. Until this, every task on screen was one the app had planted.

### Result

**Tier 1: 410 tests / 75 suites. Tier 2: 34 unit + 7 UI tests.** All green —
run [31275317887](https://github.com/emoshansari-alt/NEXT/actions/runs/31275317887).

### What was built

Manual entry, brain dump, and Capture Confirmation. `upsert(_ tasks:)` added to the repository
seam and to the shared contract. `SampleTasks` deleted along with the `emptyStoreIsSeeded`
tripwire that was guarding it — it did its job.

Decisions worth knowing:

- **Batch capture is atomic, and that is a product decision.** A brain dump is one thought,
  typed once. A partial save leaves four of seven obligations stored and three gone with nothing
  saying which — the student would have to remember what they wrote to notice. All-or-nothing
  keeps the failure recoverable: nothing saved, text still in the field.
- **`upsert(_ tasks:)` is a protocol requirement, not a defaulted loop.** A default would be
  silently non-atomic and every store would inherit the exact behaviour the method prevents.
- **Manual entry shares none of the extraction machinery.** No model, no network, no
  interpretation: the title is the text. It sits in plain sight, not behind a menu.
- **Extraction writes nothing.** `CaptureProposal` is an editing shape so an uncertain inference
  can sit on screen as a question. Note the deliberate inversion: `Validated.taskItems` *drops*
  an unconfirmed deadline so it can never reach storage; `CaptureProposal` *keeps and marks* it,
  because this screen exists to ask. Same rule from opposite ends.
- **A first run shows the empty state, and that state carries the button out of itself.**
  An app that plants tasks a student never wrote is lying to them.

### Five CI rounds, and what they were actually about

The app layer cannot be compiled on this machine, so Tier 2 is the only thing that can find
these. Every failure was mine:

1. `Package.swift` had no `platforms:`, so SwiftPM assumed macOS 10.13 and structured
   concurrency did not exist. Green on Windows, red on macOS.
2. A `TextEditor` silently swallowed typed text under automation, leaving the save button
   disabled so the tap did nothing. Replaced with a vertical-axis `TextField`.
3. The capture buttons sat behind the keyboard. Moved into a `safeAreaInset` — better product
   behaviour anyway, since capture is a screen the user types on the whole time.
4. **A container's accessibility identifier overwrites its children's.** The `VStack` marked
   `capture-saved` renamed the Done button inside it. Saving had worked the entire time; the
   suite had been failing over a name. Found by dumping `app.debugDescription` — one run of
   diagnostics beat several more of guessing.
5. A test of mine compared against `proposals.count` read *after* `confirm()` cleared it.

### Known limitations

- Nothing proves batch atomicity: neither store can be made to fail on demand through the
  protocol. Asserted by construction (staged swap in memory, single `save()` with rollback in
  SwiftData) and recorded in `TESTING.md` rather than implied away.
- No relaunch-persistence UI test. The UI target gets a fresh in-memory store per launch, so
  that needs a different arrangement.
- Dictation is not wired up, though `PRODUCT_SPEC.md` §4.5 asks for it.
- `friction` is still an explicit zero. Onboarding, Everything, Task Detail, Settings, the Focus
  timer, notifications, widget and StoreKit do not exist.

### Exact next action

**Phase 4's remainder plus Phase 7, in this order:**

1. **Everything screen** — Today / Upcoming / No deadline / Overdue / Completed, built on
   `fetch(status:)`. It is the only way to see or fix anything already captured, and right now a
   mistyped task is unreachable.
2. **Task Detail** — edit, complete, delete, break down. `TaskTransitions` already backs all of it.
3. **Rescue UI** — the whole `Rescue` module is built and tested at Tier 1 with no way to reach
   it. Four paths, wired to "I'm stuck" on Today.
4. **Onboarding** — three screens, no account.

Phase 12 note: visual assets follow **D-014** — Claude's design tooling first, Higgsfield only
for what it cannot do.

---

## 2026-08-08 — Session 3: SwiftData persistence, and the storage contract made real

**Objective.** Finish Phase 2 — put a real store behind the app.

### Result

**Tier 1: 410 tests / 75 suites. Tier 2: 20 unit + 5 UI tests.** All green —
run [31266799111](https://github.com/emoshansari-alt/NEXT/actions/runs/31266799111).
The SwiftData store passed the storage contract on its first successful compile.

### The contract was not actually shared, and now is

`verifyRepositoryContract(_:)` lived in `NextKitTests`. `NextAppTests` cannot import a test
target, so the claim that it bound *both* implementations was false — it described the
in-memory one. It now lives in a **`NextKitTestSupport` library product** that both tiers
depend on, and it **throws** instead of using `#expect`, because importing `Testing` would
restrict the target to test bundles and defeat the point.

Tier 2 now runs that identical function against SwiftData. Ordering, status partitioning,
upsert-by-identity, delete idempotence and 100-way concurrent writes are all verified against
the real store.

### What was built

`StoredTask` (`@Model`) with explicit mapping to and from `TaskItem`; `NextSchemaV1` plus a
migration plan from the first version; `SwiftDataTaskRepository` as a `@ModelActor`;
`SystemTimeSource` and `UUIDProvider` — the concrete seams that belong in the app precisely
because they may call `Date()` and `UUID()`. `TodayViewModel` now reads and writes through the
repository and recalculates from a fresh read, so the widget or a notification action changing
the same store cannot leave the screen lying.

Decisions worth knowing:

- **Decoding is lenient in one direction only.** An unknown status becomes `.active`; an
  unreadable rejection blob becomes an empty list. The task is what the student wrote down —
  metadata a future version wrote is not worth losing it over. Nothing lenient can invent a
  task or move a deadline.
- **Rejections are a JSON blob.** A small append-only list read whole or not at all does not
  earn a relationship, a delete rule and a second table. Full-precision date encoding on
  purpose: ISO-8601 truncates sub-seconds and a task would stop equalling itself after a save.
- **A container that will not open falls back to in-memory and shows a banner.** Crashing is
  worse and silently presenting an empty store is far worse — a student would assume their
  work was deleted.
- **UI tests launch with `-ui-testing`** and get a clean in-memory store. Without it the
  golden-path test, which completes a task, would slowly eat its own fixtures.

### Two CI failures, both mine

`PRODUCT_NAME` was not involved this time. The package had no `platforms:` declaration, so
SwiftPM assumed macOS 10.13 where structured concurrency does not exist — green on Windows,
red on macOS. It only surfaced now because the contract moved from a test target (newer
default) into a library target (older one).

### Known limitations

- Sample seeding still runs on an empty store. Deliberate — capture does not exist, so a first
  run would otherwise be a dead end. A test named `emptyStoreIsSeeded` is the tripwire so it is
  removed on purpose in Phase 5 rather than forgotten.
- No `TaskRepository` batch write, so a brain dump would be N awaits with no atomicity. This
  becomes a real decision in Phase 5.
- No change-notification on the repository; the view model re-reads after every write.
- Migration has one version and no stage. A round-trip test per version is required before
  release-candidate status.
- `friction` is still an explicit zero. Onboarding, Everything, Task Detail, Settings, capture,
  the Focus timer, notifications, widget and StoreKit do not exist.

### Exact next action

**Phase 5, capture.** It is what makes NEXT usable by a real person for the first time — until
then the app can only ever show tasks it invented. In order:

1. Add `upsert(_ tasks: [TaskItem])` to `TaskRepository` and decide whether it is atomic; add
   it to the shared contract so both stores are held to the answer.
2. Manual entry first — a task the user typed is the fallback that must work with no model.
3. Brain dump, using the existing `TemplateFallbackProvider` for deterministic extraction.
4. Capture Confirmation, driven by `Validated.requiresConfirmation`.
5. Delete `SampleTasks` and the `emptyStoreIsSeeded` tripwire.

---

## 2026-08-08 — Session 2: engine completed, Tier 2 live, four modules built and reviewed

**Objective.** Finish the deterministic engine, turn on Tier 2 verification, and build the
remaining `NextKit` modules.

### Headline

- **Tier 1: 410 tests in 75 suites, green** (was 16). Windows *and* `macos-latest`.
- **Tier 2 is live and passing.** The iOS app compiles under Swift 6 strict concurrency and its
  Simulator tests run: 10 unit + 5 UI, `** TEST SUCCEEDED **`, run
  [31255945755](https://github.com/emoshansari-alt/NEXT/actions/runs/31255945755).
- **`RELEASE_GATED.md` Gate A is closed.** Only paid-membership work remains gated.

### What was built

Engine completed: rejection with a decaying, finite penalty; available-time filtering;
prerequisites, blocking and unlock value; startability; the "Why this?" explanation;
`DeadlineFeasibility`. Every edge case in `PRODUCT_SPEC.md` §5 is covered.

`NextApp` first vertical slice: Today renders the recommendation, START opens Focus, Done
completes and recalculates, Not this records a rejection the engine respects, Why this? shows
the deterministic explanation. `project.yml` (XcodeGen) plus a three-job CI workflow.

Four modules via sequential subagents, each TDD'd: Support seams + Persistence + transitions ·
Rescue (8 types, all four paths) · Minimum Win · Intelligence (17 files — provider protocol,
DTOs, `ResponseValidator`, mock with all 8 failure modes, offline `TemplateFallbackProvider`).

### The adversarial review is the part worth remembering

Reviewers ran probes against shipped code rather than reasoning about it, and found 20 real
defects. The most important:

- **The academic-integrity guard was fake.** `stepsAreNeverImprovised` built its "approved copy"
  table by calling the same function the planner calls. A reviewer inserted *"Ask a friend on
  your course to send you their outline for this."* and all 43 Minimum Win tests passed.
- **Numbered substeps were silently deleted** — the dedup key stripped digits, so
  "Answer question 1/2/3" collapsed to one rung, discarding the user's own recorded work.
- **"It's too much" returned the mountain** — unestimated rungs scored as `Int.max`, so a
  45-minute chunk beat a smaller unestimated first step.
- **Capture manufactured junk tasks** — `"practice mon and wed"` → `["Practice", "Wed"]`;
  `"Chem test monday. Email professor."` → one task titled `"Chem test Email professor."`
- **The tone screen rejected legitimate coursework** — the bare stem `"diagnos"` killed
  "Read the diagnostic criteria section.", and validation fails wholesale.
- **`Clock` shadowed the standard library's `Clock`** — renamed to `TimeSource` (D-013).
- **`started()` deleted rejection *history*** to suppress a penalty that already decays,
  destroying what §14 calls the most valuable tuning signal. Now a `rejectionsSupersededAt`
  watermark instead.

**Lesson worth keeping: a test written after its implementation proves nothing until it has
been seen to fail.** Four such tests were found to be incapable of failing. Mutation testing is
now standard practice here and is documented in `TESTING.md`.

### Closed by hand after the fix round

`reassessAt` still landed exactly on the deadline for any whole-outcome rung that filled the
window (gating on `isTimeBoxed` missed it — the real condition is whether time remains after
the rung). The P5 sweep covered only `debugDescription`, so a shaming `errorDescription` via
`LocalizedError` passed — now both surfaces are swept, verified by probe. `reopened()` had no
content-preservation test; verified by mutation. Rescue's `stepNumber` was hardcoded to 1 while
`hasMoreSteps` used the real ladder index. Docs: D-013 added, an overclaimed collision mechanism
in `ARCHITECTURE.md` §3 corrected to what was actually observed, test counts refreshed.

### Known limitations

- The `friction` ranking factor still contributes an explicit zero.
- Onboarding, Everything, Task Detail, Settings, capture and capture confirmation do not exist.
- No persistence in the app yet — `TodayViewModel` holds tasks in memory and seeds from
  `SampleTasks`. SwiftData is Phase 2's remaining half.
- No Focus timer, notifications, widget or StoreKit.
- Open questions carried from subagents, none blocking: no batch write on `TaskRepository`
  (a brain dump would do N awaits with no atomicity); no change-notification on the repository;
  `TaskStatus` has no `inProgress`, so Focus cannot survive termination; `WorkKind` keyword sets
  are English-only.

### Blockers

**None.** The only remaining external requirement is paid Apple membership, and it blocks
nothing that can be built now.

### Exact next action

Phase 2's remaining half: the SwiftData-backed `TaskRepository` in `NextApp`, plus
`SystemTimeSource` and `UUIDProvider` (the concrete seams that belong in the app because they
may read the clock). Point `verifyRepositoryContract(_:)` — already written and shared — at the
SwiftData store from the Tier 2 test target, which turns the storage contract from a promise
into an enforced one. Then wire `TodayViewModel` to the repository and delete `SampleTasks`.

After that: capture and capture confirmation (Phase 5), which is what makes the app usable by
a real person for the first time.

---

## 2026-08-08 — Session 1: Phase 0 and Phase 1 foundation

**Objective.** Establish the environment, settle the platform constraint, create the repository
and documentation baseline, and get a genuinely compiling and passing core package.

### Environment findings

| Item | Result |
|---|---|
| OS | Windows 11 Home 10.0.26200 |
| Git | 2.55.0.windows.3 |
| Xcode / macOS | **Absent — macOS-only, cannot be installed here** |
| Visual Studio Build Tools 2022 | present, MSVC 14.44.35207, C++ workload present |
| Windows SDK | present |
| Swift | **installed this session** — 6.3.3, `x86_64-unknown-windows-msvc` |
| Also present | Python 3.10/3.13, Node, .NET, GitHub CLI, Android SDK |
| MCP | Higgsfield.ai bridge available (unused so far — no justified visual need yet) |

Swift was installed with `winget install --id Swift.Toolchain`. It needs the MSVC dev
environment and `SDKROOT`, neither of which is on PATH by default; `scripts/env.ps1` now
configures all of it.

### The central finding

Xcode is macOS-only, so the SwiftUI app layer cannot be compiled on this machine. This is a
**separate and earlier** constraint than the absent Apple Developer Program membership:
membership blocks distribution, the missing Mac blocks compilation.

The stack was **not** changed in response. Instead, verification was split into three tiers
(`DECISIONS.md` D-001) and the codebase was split so that the maximum amount of real logic is
provable locally (D-002). The key unlock is Tier 2: GitHub Actions `macos-latest` runners can
run `xcodebuild` and iOS Simulator tests against unsigned builds, which requires **no** paid
membership and no Mac hardware.

### Work performed

- Initialised the Git repository.
- Installed and verified the Swift 6.3.3 Windows toolchain.
- Wrote `scripts/env.ps1` (MSVC + Swift + `SDKROOT` bootstrap) and `scripts/test.ps1`.
- Created the full documentation baseline: `README.md`, `PRODUCT_SPEC.md`, `ARCHITECTURE.md`,
  `DECISIONS.md` (D-001…D-012), `TESTING.md`, `PRIVACY.md`, `RELEASE_CHECKLIST.md`,
  `RELEASE_GATED.md`, this log.
- Created the `NextKit` Swift package and its test target.
- First TDD cycle on the ranking engine's outcome states, written test-first with a verified
  RED before each implementation.

### Files created

```
.gitignore                                   scripts/env.ps1
README.md                                    scripts/test.ps1
PRODUCT_SPEC.md                              NextKit/Package.swift
ARCHITECTURE.md                              NextKit/Sources/NextKit/NextKit.swift
DECISIONS.md                                 NextKit/Sources/NextKit/Model/TaskID.swift
TESTING.md                                   NextKit/Sources/NextKit/Model/TaskStatus.swift
PRIVACY.md                                   NextKit/Sources/NextKit/Model/TaskItem.swift
RELEASE_CHECKLIST.md                         NextKit/Sources/NextKit/Ranking/RankingContext.swift
RELEASE_GATED.md                             NextKit/Sources/NextKit/Ranking/Recommendation.swift
SESSION_LOG.md                               NextKit/Sources/NextKit/Ranking/RecommendationOutcome.swift
                                             NextKit/Sources/NextKit/Ranking/RankingEngine.swift
                                             NextKit/Tests/NextKitTests/RankingEngineTests.swift
                                             NextKit/Tests/NextKitTests/Support/TestSupport.swift
```

### Tests

**Tier 1, Windows, Swift 6.3.3 — 5 tests, 5 passed, 0 failed.**

Suite `RankingEngine — outcome states`: no tasks reports nothing-to-do · all completed reports
no-active-tasks · single eligible task is recommended · completed tasks ignored when an active
one exists · archived tasks ignored.

Tier 2 and Tier 3: **not run.** Nothing exists to run there yet.

### Design decisions worth knowing

- `TaskItem`, not `Task` — avoids colliding with Swift Concurrency's `Task`.
- `TaskID` wraps a `String`, not a `UUID`, so tests can use readable ids and `NextKit` never
  needs `UUID()`.
- `recommend` returns `RecommendationOutcome`, not `Recommendation?`. An empty screen always
  carries a reason, which is what the spec's "say so clearly" requirement demands.
- Ranking is two explicit stages — filter for eligibility, then score — so an empty result is
  always explainable.

### Second TDD cycle — scoring

Added `Importance`, `RankingFactor`, `ScoringWeights`, `ScoreBreakdown`, and real factor-based
ranking. Tests written first, RED verified, then implemented.

**Tier 1 after this cycle: 16 tests, 16 passed, 0 failed.**

Design points:

- Each factor produces a normalised `0...1` signal, then gets multiplied by its weight. That
  is what makes the weights comparable to each other — a weight reads as "points at full
  strength".
- Weights: urgency 40 · overdue 25 · importance 15 · unlock 12 · startability 10 ·
  contextual fit 10 · friction −8 · rejection −60 · urgency horizon 7 days. These are a
  considered starting point, not measured truth.
- Urgency is deliberately dominant over importance, and there is a test for it: an important
  essay due in a week must not beat a normal worksheet due in an hour.
- Ordering is a **total** order (score → nearer deadline → older → id), so equal scores resolve
  identically regardless of input array order. There is a test that shuffles the input.
- Five factors — unlock, startability, contextual fit, friction, rejection — are wired in but
  return zero. They are named zeros, not omissions, and a test enforces that every factor
  appears in every breakdown so the "Why this?" explanation can never silently lose one.

### Open design question, not yet resolved

Overdue currently contributes a flat full weight with no decay. That means a task three months
overdue pins to the top permanently, which risks reading as the punishment the product
invariants forbid (P4, P5). "Not this" and archiving mitigate it, but a decay curve may be the
right answer. Needs a deliberate decision and a test — do not implement silently.

### Known limitations

- Five of the eight ranking factors are stubbed at zero (listed above).
- No "Why this?" string is generated yet, though the breakdown that feeds it exists.
- `NextApp`, `NextWidget` and `project.yml` do not exist yet.
- No CI workflow yet, so Tier 2 has never run.
- The lint checks promised in D-002 and D-007 are specified but not implemented.

### Third cycle — CI, guardrails, and the macOS unlock

Escalated one question to the owner: how NEXT should get macOS compilation. They chose a
**public GitHub repository**, which makes GitHub Actions standard runners — including macOS —
free with no minute cap.

Created and pushed **https://github.com/emoshansari-alt/NEXT** (public).

Added `.github/workflows/ci.yml` with three jobs: `guardrails` (ubuntu), `tier1` (macOS,
`swift test`), `tier2` (macOS, XcodeGen + `xcodebuild` on the Simulator).

Added `scripts/lint-nextkit.sh` enforcing D-002 and D-007. Verified it by writing a deliberate
violation probe — a file importing SwiftUI and calling `Date()` and `UUID()` — confirming all
three were caught and the exit code was 1, then deleting the probe and confirming it passed
again.

Added `.gitattributes`. This was not cosmetic: the working copy on Windows would otherwise have
pushed a CRLF shebang in the shell script, which fails on the Ubuntu runner with
"bad interpreter".

**CI run [31253999769](https://github.com/emoshansari-alt/NEXT/actions/runs/31253999769) —
all three jobs green.** Tier 1 passed 16 of 16 on `macos-latest` with Apple Swift 6.3.3, so the
suite now passes on two toolchains and two operating systems. The Tier 2 job ran and correctly
announced that `project.yml` does not exist yet.

### Gate A is closed

`RELEASE_GATED.md` Gate A (a macOS build environment) is **resolved**. Compiling the app,
Simulator tests, local StoreKit and the accessibility audit are now ordinary unfinished work,
not gated work, and have been removed from that file per its own rule. Only Gate B — paid
Apple Developer Program membership, for device testing and distribution — remains.

### Blockers

**None.** No blocker of any kind is currently outstanding. The only remaining external
requirement is paid Apple membership, and it blocks nothing that can be built now.

### Exact next action

Continue Phase 3, next TDD cycle: **rejection handling**. Write the failing tests first —

1. a task rejected within the cooldown scores below an unrejected alternative;
2. the same task is not immediately re-recommended after "Not this";
3. when the rejected task is the *only* task, it is still returned rather than a blank screen,
   and the outcome says so;
4. the penalty expires after `rejectionCooldown`.

That requires adding rejection state to `TaskItem` and a `RejectionReason` enum matching the
five reasons in `PRODUCT_SPEC.md` §4.3.

Then, in order: `estimatedMinutes` and the time-budget filter · prerequisites and unlock value ·
`nextAction` and startability · the "Why this?" explanation string built from
`ScoreBreakdown.topPositiveContributors`.

After the engine is complete, add `.github/workflows/ci.yml` so Tier 1 runs on every push and
the Tier 2 macOS job is ready the moment a GitHub repository exists.

### Commits

- `97c80b1` chore: bootstrap NEXT - docs, Windows Swift toolchain, NextKit core
- `feat(ranking): deterministic factor-based scoring` (this cycle)
