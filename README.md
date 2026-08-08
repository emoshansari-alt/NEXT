# NEXT

**Know what to do next.**

NEXT is a deliberately simple iPhone productivity app for students (~16–22) who are overwhelmed
by everything they have to do and cannot decide what to do or how to begin.

Product promise: **Open the app. Know what to do. Start.**
Product principle: **Make the next action obvious.**

Core loop: `CAPTURE → DECIDE → START → FINISH → NEXT`

NEXT is an execution assistant. It is not a planner suite, a chatbot, a mental-health app,
a social network, a habit tracker, or a general productivity platform.

---

## Start here (for a new agent or developer)

Read in this order. The repository — not any chat transcript — is the source of truth.

1. [`SESSION_LOG.md`](SESSION_LOG.md) — where the project actually is, and the exact next action
2. [`PRODUCT_SPEC.md`](PRODUCT_SPEC.md) — authoritative product definition
3. [`ARCHITECTURE.md`](ARCHITECTURE.md) — how the code is organised and why
4. [`DECISIONS.md`](DECISIONS.md) — settled technical decisions with rationale
5. [`RELEASE_GATED.md`](RELEASE_GATED.md) — work blocked purely by external/Apple requirements
6. [`TESTING.md`](TESTING.md) — test strategy, what is verified, what is not
7. `git log --oneline` — recent history

---

## Repository layout

```
NEXT/
├─ NextKit/            Pure-Swift core. No SwiftUI, no UIKit, no SwiftData.
│  ├─ Sources/         Domain models, deterministic ranking engine, rescue,
│  │                   time budgeting, AI response schema + validation.
│  └─ Tests/           Unit tests. These run on Windows, macOS and Linux.
├─ NextApp/            SwiftUI iPhone app. Compiles on macOS only.
│  ├─ Sources/
│  ├─ Tests/
│  └─ UITests/
├─ NextWidget/         WidgetKit extension. Compiles on macOS only.
├─ project.yml         XcodeGen spec — the Xcode project is generated, not committed.
├─ .github/workflows/  CI: NextKit tests everywhere, full iOS build on macOS runners.
└─ docs/               Supporting documentation and research notes.
```

The `NextKit` / `NextApp` split is deliberate and is the backbone of this project's testability.
Everything that decides *what the user should do next* lives in `NextKit` and is provable with
unit tests. `NextApp` is a thin presentation shell. See [`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## Build status by tier

Development happens on a Windows machine with no Mac hardware. Work is therefore split into
three verification tiers. Any status claim in this repository must name its tier.

| Tier | Environment | What it proves | Blocked by |
|------|-------------|----------------|------------|
| **1** | Windows + Swift toolchain (local) | `NextKit` compiles; all core logic tests genuinely pass | nothing |
| **2** | GitHub Actions `macos-latest` runner | Full app compiles; iOS Simulator unit + UI tests; accessibility audit; local StoreKit | nothing (unsigned simulator builds need no signing) |
| **3** | Physical device + Apple Developer Program | Device behaviour, TestFlight, App Store submission | paid membership — see [`RELEASE_GATED.md`](RELEASE_GATED.md) |

**Never** describe Tier 1 or Tier 2 results as device-verified or App Store ready.

---

## Local commands

Run `NextKit` tests (works on Windows, macOS, Linux):

```bash
swift test --package-path NextKit
```

Build `NextKit` only:

```bash
swift build --package-path NextKit
```

Generate and open the iOS app project (macOS only, requires XcodeGen):

```bash
xcodegen generate && open NextApp.xcodeproj
```

---

## Non-goals

NEXT 1.0 will not include: Android, web, macOS, social features, leaderboards, friends,
an AI tutor, a general assistant, GPA tracking, flashcards, note-taking, calendar replacement,
LMS/Canvas/Classroom integration, habit tracking, therapy features, a gamified pet,
a cloud backend, or collaboration.

"Complete" means NEXT reliably performs its defined job — not that it has more features.

## Licence

Not yet determined. See [`DECISIONS.md`](DECISIONS.md) D-012.
