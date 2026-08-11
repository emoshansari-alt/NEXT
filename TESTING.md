# NEXT — Testing

**Last updated:** 2026-08-09

---

## The rule that matters most

> **Never fabricate a test result, and never let a claim outrun its tier.**

Every statement about NEXT working must name where it was proven. "Tests pass" is meaningless
on its own. "All 5 `NextKit` tests pass at Tier 1 on Windows; the SwiftUI layer has never been
compiled" is a real statement.

| Tier | Environment | Command | Proves |
|------|-------------|---------|--------|
| 1 | Windows / Linux / macOS | `.\scripts\test.ps1` | `NextKit` compiles; core logic behaves |
| 2 | GitHub Actions `macos-latest` | CI workflow | App compiles; Simulator unit + UI tests; a11y audit |
| 3 | Physical device + membership | manual | Device behaviour — see [`RELEASE_GATED.md`](RELEASE_GATED.md) |

Forbidden phrasings, and what to say instead:

| Do not say | Say |
|---|---|
| "fully tested" | "all Tier 1 tests pass; Tier 2 not yet run" |
| "App Store ready" | "local release candidate; Gate B outstanding" |
| "purchase flow verified" | "entitlement logic passes at Tier 1; no purchase has ever been exercised — `RELEASE_GATED.md` B4a" |
| "AI verified" | "validated against the mock provider; no production provider has been exercised" |
| "accessible" | "automated checks pass; VoiceOver gesture verification requires a device" |

---

## Running tests

```bash
.\scripts\test.ps1
```

```bash
.\scripts\test.ps1 -Filter Ranking
```

`scripts/test.ps1` configures the MSVC toolchain, the Swift toolchain and `SDKROOT`, then runs
`swift test` in `NextKit/`. On macOS or Linux, `swift test --package-path NextKit` is equivalent.

---

## Current state — Tier 1

**Last run:** 2026-08-11 · **Result:** 568 tests in 101 suites, 568 passed, 0 failed ·
Swift 6.3.3, `x86_64-unknown-windows-msvc`

| Area | Covers |
|---|---|
| Ranking | outcome states, deadline urgency, importance, rejection, available time, prerequisites and unlocking, startability, determinism, explanation, feasibility, the decay of lateness past a deadline, friction's decided zero, all three tiers of the tie-break, the reject-and-re-rank loop, and a missing estimate's cost inside a stated window (D-025) |
| Model | task state transitions and their refusals |
| Persistence | the `TaskRepository` contract, run against the in-memory implementation |
| Rescue | all four stuck-paths, step shrinking, work-kind inference, time budgets, tone |
| Minimum Win | ladder construction, honesty constraints, substeps, time boxing, and declining once the deadline has passed (D-030) |
| Intelligence | response validation, all eight failure-injection modes, offline extraction, date parsing, brain-dump splitting, decomposition into child tasks, and every mode driven through the one write path that rewrites an *existing* task |
| Focus | timer elapsed/remaining/pause/resume, spoken countdown, neutral language, which action Focus is pointed at and what finishing it means |
| Notifications | what is and is not scheduled, the 64-notification cap, stable identifiers, tone, where tapping one lands |
| Widget | snapshot contents, staleness, JSON round trip, deep-link generation and parsing, and where a tap lands for a fresh, stale, empty, boundary-aged and future-dated snapshot |
| Everything | date bucketing into sections, ordering, partitioning |
| Monetisation | entitlement rules, expiry boundary, bounded billing-retry grace, per-receipt revocation, the capability gate, the 1.0 tripwire, the purchase contract, purchase tone |
| Design | every palette pair's contrast ratio in both appearances, the card's separation from the desk (Tier 2 — the colours are app-layer) |
| Appearance | the Dark mode switch: its default, its round trip, an unrecognised stored value, and the bool conversion the `Toggle` depends on (Tier 2 — D-027) |

The suite also runs on `macos-latest` in CI under Apple Swift 6.3.3, so it passes on two
toolchains and two operating systems.

### Guardrails

`scripts/lint-nextkit.sh` enforces D-002 (no Apple UI, persistence or notification framework in
`NextKit`) and D-007 (no `Date()` or `UUID()` in `NextKit`). It runs in CI on every push.

It has been verified against a deliberate violation probe — a file importing SwiftUI and
calling both `Date()` and `UUID()`. The lint caught all three, exited non-zero, and returned to
passing once the probe was removed. A guardrail only ever observed to pass has not been tested.

`scripts/lint-storekit.sh` holds `NextPlusProducts` and `NextApp/NEXT.storekit` to the same three
product identifiers. A typo in one of them compiles, passes every test that uses the Swift
constant, and only surfaces when a real purchase fails to resolve against App Store Connect.
Verified the same way: a deliberate `monthy` typo in the configuration made it fail with both
lists printed, and it returned to passing when the typo was removed.

`scripts/lint-app-icon.py` reads the `light:` value of every colour in `NextPalette.swift`,
decodes `AppIcon.appiconset/Icon.png` and fails when the icon is no longer made of those values,
when it is not 1024 × 1024, or when it stops being a handful of flat fills. It is **standard
library only** — the PNG is decoded with `zlib` and `struct` — because a check that needs an image
package installed is a check that gets skipped, and this one also has to run on the Windows
machine where the app cannot be compiled. Verified against a deliberate violation the same way as
the others: a one-bit nudge to `biro` made it fail with the colour named, and removing the nudge
made it pass. It exists because D-023 promised the icon could not drift from the app's colours and
named a script nobody had written (D-028, closed by D-033).

`scripts/lint-shipped-code.sh` covers **all four shipped roots** — `NextKit/Sources`,
`NextApp/Sources`, `NextApp/Shared`, `NextWidget/Sources` — which the other two do not: both are
scoped to `NextKit`. It bans force unwraps, force tries and force casts; every networking symbol;
every logging call; the shapes a credential takes (D-009); and any external package dependency
(D-010). Every one of those invariants already held when it was written, so it is not a cleanup —
it is what stops the next one, and it is what turns four release-checklist claims from things a
reader has to verify into things the build does.

The logging rule is deliberately stricter than the promise it protects. `PRIVACY.md` forbids task
text in a log; NEXT logs *nothing*, so the question of what a log line contains cannot arise. The
realistic failure is not a considered decision to log task text — it is a `print(task.title)`
added while debugging and left behind, which looks innocent in a diff.

Verified against two deliberate violation probes. The first: a file with a `URLSession`, an `x!`,
an `as!` and a `try!` was caught on all four, while the probe's `!isEmpty`, `!=` and
`"URGENT!!!"` string literal were correctly left alone. The second: a `print`, an `NSLog`, an
`apiKey` and a `"Bearer "` literal were all caught, while `tokens(in:)`, `sprint` and `footprint`
were not. Both halves matter every time — a lint that fires on `!=` or on the word "sprint" gets
disabled within a week.

Its one known limitation is stated in its own header rather than papered over: the body lines of
a multi-line `"""` literal are not stripped, so a `!` inside one would be a false positive. There
are none today.

### Mutation testing

Several behaviours here were pinned by tests written *after* the code, which means passing
proves nothing on its own. Those were validated by deliberately breaking the implementation and
confirming the test went red, then restoring it. Done so far for: prerequisite blocking, the
repository's ordering guarantee, rejection clearing on start, next-action trimming, transition
refusals, rejection preservation across `reopened()`, and the P5 language sweep. Also for the
widget's link rule: deleting the staleness check made `link(at:)` return the task instead of
Today, and the test named it.

The monetisation rules were mutation-tested as a batch when they were written, because their RED
was only a compile failure — every type was new, so "cannot find type in scope" proved the tests
referenced something, not that they could fail on behaviour. Five mutations, all caught: gating a
capability in `FeatureGate.oneDotZero`, making the expiry boundary inclusive, dropping the
per-receipt revocation filter, returning `.offerUpgrade` for an unknown entitlement, and removing
the bound on billing-retry grace. `scratchpad/mutate.py` in that session applied each in turn and
restored it; the same shape is worth repeating for any rule added here.

The ranking and intelligence work of session 12 was mutation-tested as a batch, thirteen in all
and every one caught: the deadline tie-break inverted, the rejection penalty removed, the penalty
scaled by tally instead of recency, a missing estimate treated as filling the window, the
recently-rejected flag never set, the decomposition write path made a no-op, an applicable
failure mode refusing instead of injecting, and a mode losing its applicability to `.decompose`.

Two of those attempts were **wrong mutations rather than surviving tests**, and it is worth
recording which: replacing a timeout with a *different bad payload* still fails validation, so
the store is still untouched and the test is right to stay green; and removing the refusal for an
*inapplicable* pairing changes nothing the assertion covers, by design. A survived mutation is a
question, not a verdict — the answer twice was that the mutation did not mean what it looked like.

Where a mutation could not express the risk, a **control test** does instead. "The store still
equals what it started as" only means something if that write is capable of changing the store,
so a companion test drives a *successful* decomposition through the same path and asserts the
parent really is rewritten. Without it, both tests would pass against plumbing that silently did
nothing.

`FocusTarget` was mutation-tested the same way and for the same reason. Five, all caught: making
a reduced action complete its task, re-deriving a deliberately withheld parent title from the
task, focusing the first task in the list instead of the one the rescue named, treating a
Minimum Win rung as not reduced, and using a blank recorded next action verbatim. Every one of
these is a defect that renders correctly on screen, which is exactly why they are worth pinning.

This is not ceremony. An adversarial review round found four tests that could never fail,
including the academic-integrity guard, which built its "approved copy" table by calling the
same function it was checking. Inserting an invitation to submit another student's work left
all 43 Minimum Win tests green. Any test written after its implementation must be shown to fail.

## Current state — Tier 2

**Last run:** 2026-08-09 · **Result:** `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **` ·
run [31367830604](https://github.com/emoshansari-alt/NEXT/actions/runs/31367830604)

| Target | Result |
|---|---|
| `NextApp` build (iOS Simulator, Swift 6 strict concurrency) | compiles |
| `NextAppTests` (swift-testing) | 128 tests in 29 suites, passed (2 known issues — see below) |
| `NextAppUITests` (XCTest, real Simulator) | 40 tests, passed; a 41st runs in CI's capture step |
| `NextWidgetExtension` build | compiles and installs; content unverifiable — see below |
| **Release build, app + widget, `SWIFT_TREAT_WARNINGS_AS_ERRORS`** | **builds clean — the first Release build in this repository's history** |
| Cold start (`XCTApplicationLaunchMetric`, 5 launches) | average **3.155 s**, values 2.31–4.30 s |

### What the Release build does and does not say about warnings

It says the **shipped targets** — `NextApp`, `NextWidgetExtension` and the `NextKit` package
targets they pull in — compile at `-O` with zero warnings, because a warning would have failed
that step. That is the claim the release checklist needs, and nothing in this repository had ever
measured it.

It says nothing about the **test targets**, which that step does not build, and they are not
clean: `GoldenPathUITests` produces `call to main actor-isolated instance method 'launch()' in a
synchronous nonisolated context` warnings under Swift 6. Recorded rather than quietly folded into
"no compiler warnings" — XCTest's own annotations are what makes them appear, they affect nothing
that ships, and fixing them means annotating the suite `@MainActor`, which is a change to how the
UI tests are scheduled and belongs in its own round.

The cold-start figure is recorded and **not asserted against a threshold**. A limit invented here
would be a number nobody chose, and a GitHub macOS runner is slower and busier than any phone a
student owns. A 24% relative standard deviation across five launches says so plainly.

### Two known issues, and both are the same answer

**App Groups need signing**, so the widget cannot read what the app writes. **Local StoreKit
testing needs signing**, so no purchase can be exercised. Both were found by asserting the thing
and letting CI answer, both are recorded with evidence in `RELEASE_GATED.md` (B1a and B4a), and
both are marked `withKnownIssue` so they start running for free the day signing exists.

The pattern is worth carrying forward, and is written down as D-017: an entitlement-scoped Apple
facility should be assumed Tier 3 until measured. Two of the three capabilities D-001 expected to
come free at Tier 2 turned out to need signing.

Alongside each, a test pins the *degradation* rather than only the gap: the widget's writes are
no-ops and its reads are `nil`, and the store's catalogue is empty, nothing is falsely claimed as
owned, and buying throws instead of silently doing nothing. Those are the branches that actually
run today, and they are the ones that matter — a feature that cannot reach Apple must never
become a problem the user sees.

### The App Group finding in detail

A Tier 2 test asserted the widget's shared container resolves. It does not:
`containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil` in an unsigned Simulator
build, because App Groups are *provisioned* entitlements and declaring one in `project.yml` is
not enough. Evidence:
run [31285133615](https://github.com/emoshansari-alt/NEXT/actions/runs/31285133615).

That test is now marked `withKnownIssue`, so it starts passing on its own the day signing
exists rather than needing to be remembered. Alongside it, a test asserts the *degradation* is
silent: writes are no-ops, reads are `nil`, nothing throws. The app is entirely unaffected;
only the app-to-widget handoff is gated (`RELEASE_GATED.md` B1a).

This proves the app compiles, `NextKit` links into an iOS target, the SwiftData store honours
the storage contract, and the golden path works end to end on a Simulator. It proves nothing
about a physical device — see `RELEASE_GATED.md` Gate B.

### Two lessons the UI suite taught the hard way

**A container's accessibility identifier overwrites its children's.** A `VStack` marked
`capture-saved` silently renamed the Done button inside it, and the suite failed for several CI
runs as though saving was broken. Saving had always worked. Identifiers belong on leaf views,
and tests should wait on a leaf control rather than a container.

**Existing is not the same as being tappable.** The capture buttons sat behind the keyboard;
tapping a covered control fails silently and surfaces as an unrelated assertion further down.
UI helpers now assert `isEnabled` *and* `isHittable`, and check that a text field really holds
what was typed before acting on it.

**A sheet cannot be presented while another is dismissing.** Setting one sheet false and another
true in the same tick silently swallows the second. A list should push to its own detail rather
than bouncing the presentation back through a parent screen.

**A `Form` or `List` renders its rows lazily**, so a control below the fold genuinely does not
exist yet. Scroll to it — that is part of checking it is reachable, not a workaround.

When a UI failure is not obvious, dump `app.debugDescription` rather than guessing across
ten-minute CI round-trips. That is what identified the identifier collision in one run, and it
narrowed the detail-navigation failure to its real cause in one more.

### A Swift-on-Windows compiler crash worth recognising

`paused(at: at(5))` — a helper function whose name matches an argument label, nested inside a
call using that label — reliably crashed `swiftc` 6.3.3 on Windows with:

```
error: compile command failed due to exception 3
```

No file, no line, no diagnostic. `swift build` succeeded; only the test target failed, so the
sources were not the problem. It was found by moving test files out one at a time until the
build recovered. If that error appears with no location, bisect by removing files rather than
reading the message — it has nothing more to tell you. The helper is now `mark(_:)`.

### The contracts are shared, not restated

`verifyRepositoryContract(_:)` lives in the **`NextKitTestSupport` library**, not in a test
target. Tier 1 runs it against `InMemoryTaskRepository`; Tier 2 runs *the identical function*
against SwiftData. Neither re-derives the rules, so they cannot drift.
`verifyPurchaseServiceContract(now:_:)` is built the same way — a stub at Tier 1, real StoreKit
at Tier 2, where it currently cannot run and says so.

It was moved there because the earlier version could not do this: it lived in `NextKitTests`,
which `NextAppTests` cannot import, so the claim that it bound both implementations was untrue.
It throws rather than using `#expect`, because importing `Testing` would restrict the target to
test bundles and defeat the purpose.

### Dark mode, and the check that had to measure pixels

`AppearanceUITests` turns Dark mode on through the real switch, returns to Today, and asserts the
**mean brightness of the screen** — averaged over a 32 × 32 grid, so no one has to take the
downsample on faith. Then off again, because a one-way switch is not a switch. Then a relaunch
told nothing at all, where the only thing that can make it dark is what the previous run stored.
`AccessibilityUITests` audits four screens with Dark mode on, and asserts the screen is genuinely
dark *before* auditing anything.

Two of those tests exist because of what they rule out rather than what they prove:

- **the measurement can tell two screens apart.** Two different screens in one appearance must
  measure differently. Without it a frozen screenshot is indistinguishable from a fix that changed
  nothing, and that ambiguity cost four rounds.
- **an appearance chosen at launch is measured apart from one chosen at runtime.** They are
  different mechanisms. The launch path was sound the whole time while the switch was not, and
  nothing separated them.

**A test that drives a control must assert the control moved** (D-029). `setDarkMode` checks the
switch reads what it was set to before the screen is measured at all. Four rounds concluded that
Dark mode was applied to nothing, on a screen where the switch had never been flipped:
`toggle.tap()` does not work on a `Toggle` inside a `Form`, because the control is exposed as one
Switch spanning the whole row and the tap lands on the label. A tap that never landed and an
implementation that does nothing produce the identical light screen.

`AppearanceProbe` is the other half. It reports the whole chain in one accessibility label — the
preference the root's own body saw, SwiftUI's `colorScheme`, the window's override, the trait
collection, and what `NextPalette` resolves to through `Color.resolve(in:)` — so a failure names
the broken link instead of only its outcome. It is **diagnosis, not evidence**: every value in it
is something the app says about itself, which is the failure mode that produced a green dark audit
running in light.

That looks like belt and braces and is not. Three separate failures in one session all had the
same shape — something claimed an appearance and nothing could tell it was wrong:

- `XCUIDevice.shared.appearance = .dark` **does not take effect on the CI runner**, even with a
  wait. A screen that had just asked for dark measured 0.81 — fully light. `forceAppearance` was
  deleted and every test now drives NEXT's own setting, which is both what users have and what
  works.
- The dark accessibility audit had been passing while proving nothing, because the palette clears
  4.5:1 in **both** appearances. An audit in the wrong appearance reports no issues and looks
  healthy.
- The App Store set's dark frame was captured in light, with every CI step green.

**Where an appearance cannot be read back, the pixels are the only witness.** No API reports
whether an appearance change took, so any test that claims a dark screen measures one.

### The accessibility audit

`AccessibilityUITests` runs `performAccessibilityAudit()` over every core screen, plus Today and
Focus at accessibility XXXL. It enforces `contrast`, `hitRegion`, `textClipped`,
`elementDetection`, `sufficientElementDescription` and `trait`.

**A contrast verdict is checked against the pixels it is a claim about.** `drawnContrast` crops the
element's own frame out of the screenshot the audit was judging and reports the two dominant
colours with the ratio between them; where that clears the bar with margin, the verdict is not
treated as a failure and is printed with its number instead. The audit is measurably wrong here in
both appearances — Settings' first section header is drawn at 7.14:1 and Today's empty state in
dark at 6.90:1, and it reports both (D-029). The filter can only ever *remove* a verdict its own
evidence contradicts: an element the audit reports and the pixels also fail still fails. The margin
is 5.0 rather than 4.5 because the quantisation that stops an anti-aliased fringe fragmenting moves
a ratio by a percent or two, and an element measured between the two is reported rather than argued
about.

**Contrast is enforced on the five screens NEXT draws itself** — Today, Focus, Rescue, Capture and
Onboarding — as of the Index Card palette (D-023). It is checked twice and in two different ways:
`NextPaletteTests` resolves every token pair in both appearances and asserts 4.5:1 against the
*values*, and the audit checks what is actually rendered.

Both are needed, and the difference is not academic. Turning contrast on found **four classes of
defect the palette test could not see**: an underline drawn at 45% opacity, disabled controls
dimmed below legibility, ink rendered on system row backgrounds that were never set, and section
headers left on the system's colour. The palette was correct throughout while the screens were
wrong. Equally, the palette test caught a dark card at 1.16 against the desk that no screen would
have reported.

Two categories remain **tracked rather than enforced**, both under strict `XCTExpectFailure` so
they fail the day they start passing:

- **Dynamic Type on navigation-bar buttons.** "Cancel", "Done", "Close" do not scale; SwiftUI
  offers no control over it.
- **The first section header on a system `List` or `Form`.** Everything, Task Detail, Settings and
  Minimum Win each report exactly one contrast failure, always the first header, always directly
  beneath the navigation bar. The header is NEXT's own `Text` carrying the palette's colour and
  the list style renders it against the bar's material regardless. Every *other* header on those
  screens passes, which is what identifies it as the system's rendering rather than NEXT's colour.
  Those four screens run the identical checks minus contrast.

The audit reports each issue's identifier, label and frame rather than only the fault, because the
element-level detail otherwise lives in an xcresult bundle that cannot be opened from Windows.
That change turned an unactionable "Hit area is too small" into a list of eight named controls in
one CI round.

**Capture Confirmation joined the audit in session 12**, and auditing it found five issues on a
screen that had been shipping since session 4. It was the one reachable screen the audit never
visited — `testCapturePassesTheAudit` stopped at the writing stage — so the app's only
state-carrying symbol, the include/exclude circle whose meaning is entirely in whether it is
filled, had never been put under `sufficientElementDescription`. Eleven screen states are now
audited.

What it found, and why each is worth recording:

- **The include/exclude control had no minimum target.** A symbol's own bounds were the entire
  hit area on the control that decides whether a captured task is kept at all.
- **"Clear" was a caption-height text button**, about fourteen points tall. This is the same
  class as the eight controls the audit's first run found, and it survived because nothing had
  looked at this screen.
- **The screen had never been restyled to the palette**: five system `.secondary` colours and no
  card row background — the identical omission that produced eight failures on Settings and six
  on Task Detail when contrast was first enforced.
- **"Edit" failed contrast as NEXT's ink on a `.bar` material.** That is D-021's section-header
  finding in a different place, and it generalises: *a material has no colour the palette can be
  measured against, so any text NEXT draws on one is unverifiable by construction.* Both capture
  bars now use `NextPalette.card`, a value `NextPaletteTests` already proves the ink tokens
  against.

**The audit skips the system keyboard, and only the system keyboard.** Capture focuses its field
on appear, which is the right state to audit — it is the state the user is in, and the reason the
action bar sits in a safe-area inset — but the audit walks the keyboard's own QuickType bar too:
three unlabelled 140 × 44 slots no app can label, style or remove. An issue is skipped only if it
overlaps the keyboard **and** its element carries no identifier. A frame test alone would have
exempted the two action buttons an earlier round found unreachable at accessibility sizes; every
control NEXT draws carries an identifier, so an unidentified one over the keyboard is the
keyboard's, and an unlabelled element anywhere else still fails.

Its first run found issues on all ten core screens. Eleven were fixed: eight controls below
44 × 44 — every one a plain text button whose hit area was a line of text tall — and three clipped
labels. **Two of the remaining failures were regressions the audit itself caught**: giving a
button room to wrap, to stop it clipping at the default size, made Capture's action bar taller
than the space above the keyboard at accessibility XXXL, so the save button stopped being
reachable. That is a defect invisible at the size a developer looks at, introduced while fixing a
different accessibility defect, and found within one run.

**A green audit is not a claim that NEXT is accessible.** VoiceOver gesture traversal, rotor
behaviour, real Dynamic Type rendering and haptics need hardware — `RELEASE_GATED.md` B5. It is
the smaller, true claim that the automatable checks pass.

### Persistence across relaunch — closed

The oldest gap in this file, carried since Session 3, is verified as of run
[31293153742](https://github.com/emoshansari-alt/NEXT/actions/runs/31293153742). The full cycle
runs: create → terminate → relaunch → verify → edit → terminate → relaunch → verify the edit →
complete → terminate → relaunch → verify it is filed rather than deleted.

It needed a launch mode of its own. `-ui-testing` swaps in a fresh in-memory container per launch
so the golden path cannot consume its own fixtures, which is right for every other test and fatal
for this one: against a store recreated on launch, "relaunch and verify" passes no matter what the
persistence layer does. `-ui-store-name` puts a real SwiftData store on disk in a throwaway
location, and `-ui-reset-store` clears it on a test's first launch only.

**Three of its assertions passed for the wrong reason first**, which is worth recording. An
Everything row is a `Button` carrying its own accessibility label, so the title inside it is not a
separate element — the container's label replaces its children's, the same lesson recorded above.
Searching `staticTexts` for the title matched *Today*, sitting behind the sheet showing the same
title. It only came apart when the task was completed and Today fell back to its empty state. A UI
assertion that never looked at the screen it names is the same failure the mutation-testing rule
exists to catch, and it applies to UI tests too.

### UI tests run against a clean store

The UI target launches the app with `-ui-testing`, which swaps in an in-memory container.
Without it the suite would share the simulator's real database and the golden-path test — which
completes a task — would consume its own fixtures until nothing was left to recommend. A test
whose result depends on how many times it has run before is not a test.

One test adds `-ui-seed-unreachable`, which seeds a single task due in forty-five minutes with a
three-hour estimate. It does nothing unless `-ui-testing` is also present. Minimum Win needs a
deadline that is close but *not* passed together with an estimate that does not fit, and Task
Detail's date picker defaults to the current instant — leaving no window at all. Driving a
`DatePicker` to a specific future time through XCUITest is fiddly and flaky, and a flaky test of
a real flow is worth less than an honest fixture for it.

### Not yet written

Required by the product spec and **not** yet covered. Tracked honestly rather than implied away:

- the `friction` ranking factor contributes zero **by decision**, not by omission —
  D-022, pinned by `RankingFrictionTests`
- **notification delivery.** The plan and the routing are verified; nothing asserts anything
  arrives. Delivery needs a device — `RELEASE_GATED.md` B5.
- **a real purchase**, and the receipt mapping behind it — `RELEASE_GATED.md` B4a
- **the widget's rendered content**, which needs a shared container — B1a
- notification *actions* — deliberately out of 1.0 scope; §8 specifies categories, contextual
  permission and real controls, and does not ask for them

---

## Test design rules

**Determinism is enforced, not hoped for.** `NextKit` may not call `Date()` or `UUID()`
(`DECISIONS.md` D-007). Tests pin "now" to `Date.testReference`
(Tuesday 10 March 2026, 09:00 UTC) and use readable identifiers such as `TaskID("chem")`.
A deadline test therefore expresses "due in 3 hours" exactly, not approximately.

**Real code over mocks.** Mocks are used only at genuine boundaries — the intelligence
provider, the clock, the repository. Business logic is always tested against the real
implementation.

**One behaviour per test.** If a test name contains "and", it is two tests.

**Test names state behaviour, not method names.** `"ignores completed tasks when an active one
exists"`, not `"testFilter"`.

---

## Required coverage before release-candidate status

### Unit — Tier 1

ranking and every scoring factor · deadline weighting · rejection penalties · task state
transitions · duration logic · AI response validation · fallback behaviour · persistence
mapping logic · rescue logic · Minimum Win · time budgeting.

### Integration — Tier 2

capture → confirmation → persistence · task → Focus → completion · recommendation
recalculation after completion · notification scheduling logic · entitlement logic.

### UI — Tier 2

The golden path, end to end:

```
fresh install → onboarding → brain dump → extraction → confirmation
→ NEXT recommendation → START → Focus → complete → new recommendation
→ terminate → relaunch → state correct
```

### Offline — split by what each tier can actually prove

The original wording of this section asked for the golden path "with the network disabled". No
tier can run that. There is no `XCUIDevice` or `simctl` control for airplane mode; the Simulator
shares the host's network stack, so the only lever is a host-level one, and on the CI runner
turning it would sever the runner's own connection to GitHub Actions. An item no tier can ever
tick is not a strict standard, it is a permanently unticked box that stops meaning anything.

Split into three claims, each provable where it is written:

1. **Guardrail — no first-party networking exists.** `scripts/lint-shipped-code.sh` fails the
   build if any shipped source names `URLSession`, `URLRequest`, `Network`, `WebKit`,
   `Data(contentsOf:)` or the rest of the list, across all four shipped roots. This matters
   because `URLSession` comes from Foundation: adding one needs no new import and would have
   passed every check that existed before. It proves no first-party file *names* a networking
   API. It does not prove no packet left the device.
2. **Tier 1 — the offline provider answers with no network, key or consent.**
   `TemplateFallbackProvider` is the shipping default in both view models that take a provider,
   so this is not a fallback path, it is the path.
3. **Tier 2 — the whole loop runs with no provider answering.** Capture, recommendation, Focus,
   completion, relaunch and persistence all run green with the offline provider in place
   (`PersistenceUITests`, `GoldenPathUITests`), which is the substantive half of the claim: NEXT
   is fully usable when the intelligence layer says nothing.

**Tier 3, with the radio genuinely off**, stays in `RELEASE_GATED.md` as a device observation.
That is the only place the literal claim can be made, and it is not made anywhere else.

### AI failure injection — Tier 1

The mock provider must be driven through every one of these, and none may crash or corrupt
stored data:

timeout · malformed JSON · empty response · impossible date · unreasonable duration · missing
required field · invalid enum value · partial response.

### Recommendation loop — Tier 1

Reject a recommendation; the same task must not immediately return unless there is genuinely no
alternative — and in that case the engine must say so explicitly rather than silently recycling
it.

### Persistence — Tier 2

Create → terminate → relaunch → verify → modify → terminate → relaunch → verify → complete →
terminate → relaunch → verify.

### Accessibility — Tier 2 automated, Tier 3 manual

**By the audit** (`performAccessibilityAudit`, on a rendered screen): labels present, contrast,
touch-target size, element detection, traits, Dynamic Type layout at the largest sizes.

**By Tier 2 unit tests**, because the audit structurally cannot see them: that Reduce Motion
selects the still curve *and* that the two curves differ, so the pair cannot become vacuous; and
when a failure message is announced — on appearance, not on clearing, and never twice for the
same message. XCUITest cannot hear VoiceOver speak, so the decision about *when* to speak is a
pure function that is tested, and the line that hands the string to the system is one statement
with no logic in it.

**Device-only, and documented as such**: real VoiceOver gesture traversal, real rotor behaviour,
whether an announcement is actually spoken, and real haptics.
