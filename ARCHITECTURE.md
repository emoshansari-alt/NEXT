# NEXT — Architecture

**Last updated:** 2026-08-08

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
│   MinimumWin/       MinimumWinPlanner                        │
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

**Rule:** no call to `Date()`, `UUID()`, or `Task.sleep` anywhere in `NextKit`. A lint check
enforces this. Ranking must be a pure function of `(tasks, context, weights, now)`.

The time seam is **not** called `Clock`. The standard library already vends that name, and a
second one shadows it: in any file importing `NextKit`, `Swift.Clock` would stop being nameable
unqualified and `ContinuousClock` would stop appearing to conform to plain `Clock`. Where both
modules are visible on equal footing the unqualified name is an outright ambiguity the caller
has to resolve by hand at every use. `TimeSource` collides with nothing and needs no
qualification anywhere. `SupportSeamTests` pins this by naming `Swift.Clock` unqualified.

Both storage and time are pinned by shared, reusable checks rather than by assertions that only
exist in one place: `verifyRepositoryContract(_:)` runs the whole `TaskRepository` contract
against any implementation, so `NextApp`'s Tier 2 target can point it at the SwiftData store and
get the identical promises verified.

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

Full `xcodebuild` of `NextApp` and `NextWidget`, iOS Simulator unit and UI tests, accessibility
audit, and local StoreKit `.storekit` testing. Requires **no** Apple Developer Program
membership: simulator builds are unsigned. This is the tier that verifies the SwiftUI layer.

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
- No unexplained magic constants — scoring constants live in `ScoringWeights`, UI constants in
  a design-token file.
- No force unwraps outside tests.
- No dead experiments and no permanent "temporary" hacks in shipped code.
- Prefer boring, comprehensible engineering over architectural elegance.

## 11. Dependency policy

Native Apple frameworks are the default. Every third-party dependency must justify its
maintenance, privacy, security and compatibility cost in `DECISIONS.md` before adoption.
Current third-party runtime dependencies: **none**.
