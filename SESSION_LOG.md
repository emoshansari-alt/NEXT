# NEXT — Session Log

Newest entry first. This file is the project's memory. A new agent should be able to read this
plus `PRODUCT_SPEC.md`, `ARCHITECTURE.md` and `DECISIONS.md` and resume with no chat history.

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
