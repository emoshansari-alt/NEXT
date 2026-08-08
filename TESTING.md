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

**Last run:** 2026-08-08 · **Result:** 16 tests, 16 passed, 0 failed · Swift 6.3.3,
`x86_64-unknown-windows-msvc`

| Suite | Tests | Status |
|---|---|---|
| `RankingEngine — outcome states` | 5 | passing |
| `RankingEngine — deadline urgency` | 5 | passing |
| `RankingEngine — importance` | 2 | passing |
| `RankingEngine — determinism` | 4 | passing |

Also verified in CI on `macos-latest` (Apple Swift 6.3.3): 16 of 16 passing —
run [31253999769](https://github.com/emoshansari-alt/NEXT/actions/runs/31253999769).
The same suite therefore passes on two toolchains and two operating systems.

### Guardrails

`scripts/lint-nextkit.sh` enforces D-002 (no Apple UI, persistence or notification framework in
`NextKit`) and D-007 (no `Date()` or `UUID()` in `NextKit`). It runs in CI on every push.

It has been verified against a deliberate violation probe — a file importing SwiftUI and
calling both `Date()` and `UUID()`. The lint caught all three, exited non-zero, and returned to
passing once the probe was removed. A guardrail only ever observed to pass has not been tested.

### Current state — Tier 2

**Never run against real code.** The Tier 2 job exists and executes, but `NextApp` and
`NextWidget` do not exist yet, so the job reports that and does nothing. It is deliberately
loud about this: a job passing because there was nothing to do must never be mistaken for one
passing because the app compiled.

### Not yet written

The following are required by the product spec and are **not** yet covered. Their absence is
tracked here honestly rather than implied away:

- unlock/prerequisite value · startability · contextual fit · friction · rejection penalty
  (these five factors currently contribute an explicit zero)
- every remaining ranking edge case in `PRODUCT_SPEC.md` §5 — impossible deadline, task longer
  than available time, blocked task, completed parent with pending child, missing duration,
  all tasks unavailable
- the "Why this?" explanation string
- task state transitions
- rescue strategies (all four paths)
- time-budget selection
- Minimum Win planning
- AI response validation and every malformed-response case
- fallback provider extraction
- repository semantics

### Never compiled

`NextApp` and `NextWidget` do not exist yet. When they do, they remain **UNVERIFIED** until
Tier 2 runs. No claim about them is permitted before then.

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
