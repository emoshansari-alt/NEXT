# NEXT — Architecture

**Last updated:** 2026-08-09

---

## 1. The central structural idea

> Everything that decides *what the user should do next* lives in a pure-Swift module with no
> Apple UI dependencies, and is proven by unit tests. The SwiftUI app is a thin shell over it.

This yields three benefits at once:

1. **Testability.** The ranking engine, rescue logic and AI validation are deterministic pure
   functions over value types. They are trivially unit-testable and have no simulator dependency.
2. **Portability of verification.** Because `NextKit` depends only on Foundation, it compiles and
   its tests genuinely *run* on Windows and Linux — not only on macOS. This is what makes real
   progress possible on the current development machine (see §6).
3. **Replaceability.** Persistence and intelligence are behind protocols. SwiftData can be swapped
   for Core Data, and any model provider can be swapped, without touching product logic.

---

## 2. Module map

```
┌──────────────────────────────────────────────────────────────┐
│ NextWidget          WidgetKit extension (macOS-only build)   │
├──────────────────────────────────────────────────────────────┤
│ NextApp             SwiftUI views, navigation, view models,  │
│                     SwiftData store, notifications, StoreKit,│
│                     haptics, deep links   (macOS-only build) │
├──────────────────────────────────────────────────────────────┤
│ NextKit             ← pure Swift, Foundation only            │
│   Model/            Task, Substep, Importance, TaskStatus,   │
│                     Rejection, TaskSource, Estimate          │
│   Ranking/          RankingEngine, ScoringWeights, Factor,   │
│                     Recommendation, Explanation              │
│   Rescue/           RescueStrategy, StepShrinker, WorkKind,  │
│                     RescuePath, TimeBudget, RescueFraming,   │
│                     RescueStep, RescueStepOrigin,            │
│                     RescueResponse, RescueOutcome            │
│   Focus/            FocusSession, FocusTarget               │
│   MinimumWin/       MinimumWinPlanner                        │
│   Monetisation/     NextTier, EntitlementState, Resolver,    │
│                     FeatureGate, PremiumCapability,          │
│                     NextPlusProducts, PurchaseService        │
│   Intelligence/     IntelligenceProvider, request/response   │
│                     DTOs, ResponseValidator, MockProvider,   │
│                     TemplateFallbackProvider                 │
│   Persistence/      TaskRepository protocol (+ in-memory)    │
│   Support/          TimeSource, IDProvider, Logging seam     │
└──────────────────────────────────────────────────────────────┘
```

Dependency direction is strictly downward. `NextKit` imports nothing from `NextApp`.

### What may never appear in `NextKit`

`import SwiftUI` · `import UIKit` · `import SwiftData` · `import WidgetKit` · `import StoreKit` ·
`import UserNotifications` · any network client · any third-party package.

A CI check enforces this. If it ever needs one of those, the design is wrong.

---

## 3. Determinism seams

Non-determinism is injected, never reached for directly. This is what makes the engine testable.

| Seam | Protocol | Production | Test |
|------|----------|------------|------|
| Current time | `TimeSource` | `SystemTimeSource` | `FixedTimeSource(instant:)` |
| Identifiers | `IDProvider` | `UUIDProvider` | `SequentialIDProvider` |
| Intelligence | `IntelligenceProvider` | on-device / cloud | `MockIntelligenceProvider` |
| Storage | `TaskRepository` | SwiftData-backed | `InMemoryTaskRepository` |
| Purchases | `PurchaseService` | `StoreKitPurchaseService` | a stub, per test |

**Rule:** no call to `Date()`, `UUID()`, or `Task.sleep` anywhere in `NextKit`. A lint check
enforces this. Ranking must be a pure function of `(tasks, context, weights, now)`.

The time seam is **not** called `Clock`. The standard library already vends that name — the
protocol behind `ContinuousClock` and `Task.sleep(until:)` — and a second one competes with it
in any file importing both.

The cost was observed rather than assumed: while the seam was still called `Clock`, its own
test file could not conform to it without writing `NextKit.Clock`, and had to spell the
existential `any NextKit.Clock`. Which uses resolve silently and which the compiler rejects
depends on what else is in scope, and having to work that out per call site is the problem.
`TimeSource` collides with nothing and needs no qualification anywhere. `SupportSeamTests`
pins this by naming `Swift.Clock` unqualified.

Both storage and time are pinned by shared, reusable checks rather than by assertions that only
exist in one place: `verifyRepositoryContract(_:)` runs the whole `TaskRepository` contract
against any implementation, so `NextApp`'s Tier 2 target can point it at the SwiftData store and
get the identical promises verified. `verifyPurchaseServiceContract(now:_:)` does the same for
purchases — a stub at Tier 1, real StoreKit under a test session at Tier 2.

---

## 4. The ranking engine

`RankingEngine.recommend(from:context:) -> Recommendation?`

It is a pure function. Given the same tasks, the same context and the same `now`, it always
returns the same answer, and always returns an explanation alongside the choice.

### Score composition

Each factor is a named, bounded contribution — not an anonymous number. This is what makes
"Why this?" possible without an LLM: the explanation is generated from the top-contributing
factors of the winning task.

```swift
struct ScoreBreakdown {
    var factors: [RankingFactor: Double]   // every factor, always populated
    var total: Double
}
```

Factors: `deadlineUrgency`, `importance`, `unlockValue`, `overdueRelevance`, `startability`,
`contextualFit`, `friction` (negative), `rejectionPenalty` (negative).

All weights live in a single `ScoringWeights` value type with documented defaults. No scoring
constant appears anywhere else in the codebase.

### Eligibility vs. scoring

Two distinct stages, kept separate so failures are explainable:

1. **Filter** — remove tasks that are ineligible right now (completed, blocked by an incomplete
   prerequisite, longer than the available time window, hard-excluded by an active rejection).
2. **Score** — rank what remains.

If the filter empties the list, NEXT reports *why* it is empty rather than recommending
something ineligible. This directly satisfies the "no viable alternative exists — say so" rule.

---

## 5. Intelligence layer

```
        App feature (capture, rescue, decompose)
                        │
                 IntelligenceProvider          ← protocol, async, throwing
                        │
        ┌───────────────┼────────────────┬──────────────────┐
   OnDevice          Cloud            Mock          TemplateFallback
   (gated by       (gated by       (tests, CI)     (deterministic,
    availability)   consent +                       always available,
                    key policy)                     no network)
                        │
                 ResponseValidator               ← the mandatory gate
                        │
                 validated value types
                        │
                 repository mutation
```

**The validator is not optional and not bypassable.** Every provider's output crosses it before
any state mutation. It enforces: required fields present, enums in range, dates parseable and
sane, durations within plausible bounds, string lengths bounded, and confidence scores in
`0...1`. Anything that fails is rejected wholesale — never partially applied.

Low-confidence deadlines do not fail validation; they are flagged and routed to Capture
Confirmation for the user to resolve. Silent invention of certainty is a defect.

`TemplateFallbackProvider` is the reason NEXT works offline. It performs deterministic
extraction (date phrases, list splitting) and template-based rescue decomposition with no model
of any kind. It is always present and is the last resort in the chain.

Provider selection research is deferred to Phase 8 and will be recorded in `DECISIONS.md`.

---

## 6. Build and verification tiers

Development is on Windows; Xcode is macOS-only. Work is therefore split by where it can be
*proven*, and every status claim must name its tier.

### Tier 1 — local Windows (`swift test --package-path NextKit`)

Genuinely compiled and genuinely executed: all of `NextKit`. This covers the ranking engine,
rescue logic, Minimum Win, time budgeting, response validation, the fallback provider, task
state transitions, and repository semantics against the in-memory implementation.

### Tier 2 — GitHub Actions `macos-latest`

Full `xcodebuild` of `NextApp` and `NextWidget`, iOS Simulator unit and UI tests, the
accessibility audit in **both** appearances, a Release build with warnings as errors, and the App
Store screenshot capture. Requires **no** Apple Developer Program membership: simulator builds are
unsigned. This is the tier that verifies the SwiftUI layer.

Two things once expected here turned out to need signing, and both were found by asserting them
rather than assuming either way: **App Groups**, so the widget cannot read what the app writes
(`RELEASE_GATED.md` B1a), and **local StoreKit testing**, so no purchase can be exercised against
a `.storekit` configuration (B4a). Both are entitlement-scoped Apple facilities, and an unsigned
build carries no entitlements. Everything those features decide is still proven at Tier 1;
what is gated is only the part that requires Apple to answer.

### Tier 3 — physical device + paid membership

Device behaviour, real notification delivery, real widget timeline behaviour, TestFlight,
submission. Everything here is tracked in `RELEASE_GATED.md`.

Anything authored but not yet compiled by Tier 2 is marked `UNVERIFIED` in `TESTING.md`.
It is never described as working.

---

## 7. Xcode project generation

The `.xcodeproj` is **generated from `project.yml` by XcodeGen** and is gitignored.

Rationale: a hand-authored `project.pbxproj` cannot be reliably created or reviewed from a
Windows machine, is merge-hostile, and silently drifts. A declarative YAML spec is reviewable,
diffable, and reproducible with one command on any Mac or CI runner. See `DECISIONS.md` D-003.

---

## 8. App-layer structure (`NextApp`)

Plain MVVM. No architecture framework, no dependency-injection container, no reactive
abstraction layer beyond what SwiftUI already provides.

- **Views** are dumb. They render state and send intents.
- **View models** are `@Observable` classes holding view state and calling into `NextKit` and
  the repositories.
- **Services** wrap platform capabilities behind protocols: `NotificationScheduling`,
  `EntitlementProviding`, `HapticFeedback`, `HealthOfStore`.
- **Store** is SwiftData, reached only through `TaskRepository`. No view touches a
  `ModelContext` directly.

The point of the protocol wrappers is that view models remain testable on the simulator without
real notification permission, real purchases, or real hardware.

### The design system is shared with the widget

`NextApp/Shared/Design` is compiled into both the app and the widget target, for the same reason
`SnapshotStore` is: the widget must be the same object as the card in the app, and two copies of a
palette drift. It is view modifiers and value types with no state, so sharing costs nothing at
launch — an embedded framework would, in an extension expected to render in milliseconds.

### What crosses between screens is a value, not a task

Rescue and Minimum Win both answer with a deliberately *smaller* action than the task it came
from. Handing a screen a bare `TaskItem` cannot express that — a task can only describe itself —
and the result was a real defect: a rescued step was computed, displayed, and then dropped, so
"Do that" opened Focus on the mountain the user had just said was too much.

`FocusTarget` (in `NextKit`, not in a view) carries the task, the action, where the action came
from, and whether it is reduced. Everything that follows from that — which task to resolve, which
words to show, and whether finishing completes anything — is a rule with a Tier 1 test rather
than a convention a view is trusted to honour. See D-018.

The general shape is worth reusing: when a screen's answer is *narrower* than its input, the
narrowing belongs in a value that the next screen cannot widen again by accident.

---

## 9. Data and migration

SwiftData `@Model` types live in `NextApp` and map to/from `NextKit` value types at the
repository boundary. The domain layer therefore never depends on the persistence framework, and
a migration to Core Data would touch one module.

Migration strategy is defined before release-candidate status: versioned schema, a documented
migration plan, and a round-trip test per schema version.

---

## 10. Code quality rules

- No god objects; no file grows large merely because splitting is effort.
- No duplicated business logic between `NextKit` and `NextApp`.
- No unexplained magic constants — scoring constants live in `ScoringWeights`, and every colour,
  font, radius and duration lives in `NextApp/Shared/Design` (D-023). A hex value or a point size
  written anywhere else is a defect, not a shortcut.
- No force unwraps outside tests.
- No dead experiments and no permanent "temporary" hacks in shipped code.
- Prefer boring, comprehensible engineering over architectural elegance.

## 11. Dependency policy

Native Apple frameworks are the default. Every third-party dependency must justify its
maintenance, privacy, security and compatibility cost in `DECISIONS.md` before adoption.
Current third-party runtime dependencies: **none**.
