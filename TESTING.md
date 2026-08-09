# NEXT — Testing

**Last updated:** 2026-08-08

---

## The rule that matters most

> **Never fabricate a test result, and never let a claim outrun its tier.**

Every statement about NEXT working must name where it was proven. "Tests pass" is meaningless
on its own. "All 5 `NextKit` tests pass at Tier 1 on Windows; the SwiftUI layer has never been
compiled" is a real statement.

| Tier | Environment | Command | Proves |
|------|-------------|---------|--------|
| 1 | Windows / Linux / macOS | `.\scripts\test.ps1` | `NextKit` compiles; core logic behaves |
| 2 | GitHub Actions `macos-latest` | CI workflow | App compiles; Simulator unit + UI tests; a11y audit; local StoreKit |
| 3 | Physical device + membership | manual | Device behaviour — see [`RELEASE_GATED.md`](RELEASE_GATED.md) |

Forbidden phrasings, and what to say instead:

| Do not say | Say |
|---|---|
| "fully tested" | "all Tier 1 tests pass; Tier 2 not yet run" |
| "App Store ready" | "local release candidate; Gate B outstanding" |
| "purchase flow verified" | "local StoreKit entitlement logic passes; sandbox verification is release-gated" |
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

**Last run:** 2026-08-09 · **Result:** 516 tests in 96 suites, 516 passed, 0 failed ·
Swift 6.3.3, `x86_64-unknown-windows-msvc`

| Area | Covers |
|---|---|
| Ranking | outcome states, deadline urgency, importance, rejection, available time, prerequisites and unlocking, startability, determinism, explanation, feasibility |
| Model | task state transitions and their refusals |
| Persistence | the `TaskRepository` contract, run against the in-memory implementation |
| Rescue | all four stuck-paths, step shrinking, work-kind inference, time budgets, tone |
| Minimum Win | ladder construction, honesty constraints, substeps, time boxing |
| Intelligence | response validation, all eight failure-injection modes, offline extraction, date parsing, brain-dump splitting, decomposition into child tasks |
| Focus | timer elapsed/remaining/pause/resume, spoken countdown, neutral language |
| Notifications | what is and is not scheduled, the 64-notification cap, stable identifiers, tone |
| Widget | snapshot contents, staleness, JSON round trip, deep-link generation and parsing |
| Everything | date bucketing into sections, ordering, partitioning |
| Monetisation | entitlement rules, expiry boundary, bounded billing-retry grace, per-receipt revocation, the capability gate, the 1.0 tripwire, the purchase contract, purchase tone |

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

### Mutation testing

Several behaviours here were pinned by tests written *after* the code, which means passing
proves nothing on its own. Those were validated by deliberately breaking the implementation and
confirming the test went red, then restoring it. Done so far for: prerequisite blocking, the
repository's ordering guarantee, rejection clearing on start, next-action trimming, transition
refusals, rejection preservation across `reopened()`, and the P5 language sweep.

The monetisation rules were mutation-tested as a batch when they were written, because their RED
was only a compile failure — every type was new, so "cannot find type in scope" proved the tests
referenced something, not that they could fail on behaviour. Five mutations, all caught: gating a
capability in `FeatureGate.oneDotZero`, making the expiry boundary inclusive, dropping the
per-receipt revocation filter, returning `.offerUpgrade` for an unknown entitlement, and removing
the bound on billing-retry grace. `scratchpad/mutate.py` in that session applied each in turn and
restored it; the same shape is worth repeating for any rule added here.

This is not ceremony. An adversarial review round found four tests that could never fail,
including the academic-integrity guard, which built its "approved copy" table by calling the
same function it was checking. Inserting an invitation to submit another student's work left
all 43 Minimum Win tests green. Any test written after its implementation must be shown to fail.

## Current state — Tier 2

**Last run:** 2026-08-09 · **Result:** `** TEST SUCCEEDED **` ·
run [31286116920](https://github.com/emoshansari-alt/NEXT/actions/runs/31286116920)

| Target | Result |
|---|---|
| `NextApp` build (iOS Simulator, Swift 6 strict concurrency) | compiles |
| `NextAppTests` (swift-testing) | 66 tests in 15 suites, passed (1 known issue — see below) |
| `NextAppUITests` (XCTest, real Simulator) | 13 tests, passed |
| `NextWidgetExtension` build | compiles and installs; content unverifiable — see below |

### The one known issue: App Groups need signing

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

### The storage contract is shared, not restated

`verifyRepositoryContract(_:)` lives in the **`NextKitTestSupport` library**, not in a test
target. Tier 1 runs it against `InMemoryTaskRepository`; Tier 2 runs *the identical function*
against SwiftData. Neither re-derives the rules, so they cannot drift.

It was moved there because the earlier version could not do this: it lived in `NextKitTests`,
which `NextAppTests` cannot import, so the claim that it bound both implementations was untrue.
It throws rather than using `#expect`, because importing `Testing` would restrict the target to
test bundles and defeat the purpose.

### UI tests run against a clean store

The UI target launches the app with `-ui-testing`, which swaps in an in-memory container.
Without it the suite would share the simulator's real database and the golden-path test — which
completes a task — would consume its own fixtures until nothing was left to recommend. A test
whose result depends on how many times it has run before is not a test.

### Not yet written

Required by the product spec and **not** yet covered. Tracked honestly rather than implied away:

- the `friction` ranking factor still contributes an explicit zero
- onboarding, Everything, Task Detail, Settings, capture and capture confirmation — the screens
  do not exist yet, so neither do their tests
- the Focus timer
- persistence across relaunch (needs SwiftData, which needs the app-layer store)
- notification scheduling logic
- StoreKit entitlement logic
- the automated accessibility audit
- integration tests spanning capture → confirmation → persistence

### Never compiled

`NextWidget` does not exist. It remains **UNVERIFIED** until Tier 2 builds it.

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

### Offline — Tier 2

With the network disabled: manual task creation → recommendation → Focus → complete → relaunch
→ state persists. The core app must work with no cloud AI of any kind.

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

Automated: labels present, contrast, touch-target size, Dynamic Type layout at the largest
sizes, Reduce Motion honoured.
Device-only, and documented as such: real VoiceOver gesture traversal, real rotor behaviour,
real haptics.
