# NEXT — Session Log

Newest entry first. This file is the project's memory. A new agent should be able to read this
plus `PRODUCT_SPEC.md`, `ARCHITECTURE.md` and `DECISIONS.md` and resume with no chat history.

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

### Known limitations

- `NextKit` currently returns the first eligible task. **There is no scoring yet.** This is the
  next piece of work, not an oversight.
- `NextApp`, `NextWidget` and `project.yml` do not exist yet.
- No CI workflow yet, so Tier 2 has never run.
- The lint checks promised in D-002 and D-007 are specified but not implemented.

### Blockers

None blocking ordinary development.

**One open question for the owner** (does not block current work — see next action):
whether a GitHub repository can be created, which is what turns on Tier 2 verification. It
needs no Apple account and no payment. Until then the SwiftUI layer can be authored but never
compiled, and must stay marked UNVERIFIED.

### Exact next action

Continue Phase 3. Next TDD cycle: `ScoringWeights` and deadline-urgency scoring — write the
failing tests for "recommends the sooner deadline", "an overdue task outranks a future one",
and "a task with no deadline ranks below one with a deadline", then implement
`ScoreBreakdown` and factor-based ranking in `RankingEngine`.

After the engine has scoring, add `.github/workflows/ci.yml` so Tier 1 runs on every push and
the Tier 2 macOS job is ready the moment a repository exists.

### Commit

`chore: bootstrap NEXT — docs, Windows Swift toolchain, NextKit core` (see `git log`)
