# NEXT — Release Checklist

Two lists. The first is work that must be finished **before** NEXT can be called a
**Local Release Candidate**. The second is everything gated on Apple, which lives in
[`RELEASE_GATED.md`](RELEASE_GATED.md) and is only summarised here.

**Last updated:** 2026-08-09

---

## Part 1 — Local Release Candidate

The term "Local Release Candidate" may not be used until every box below is ticked with
evidence. Ticking a box without a passing test or a named verification is a violation of the
honesty policy in [`TESTING.md`](TESTING.md).

### Product completeness

Ticked means the surface exists and is Tier 2 verified. It does **not** mean device-verified —
see `RELEASE_GATED.md` Gate B.

- [x] Onboarding — three screens, no account, contextual permissions
- [x] Today / NEXT — single dominant recommendation
- [x] Something else — rejection with reasons and a temporary penalty. Labelled `Not this`
      until session 14; the behaviour is unchanged
- [x] Why this one — deterministic explanation, works offline, and shown **on the card** rather
      than behind a control (PRODUCT_SPEC.md §4.4). The `Why this?` link is retired: it repeated
      the card for any task with a deadline
- [x] Capture — manual entry
- [x] Capture — brain dump with extraction
- [x] Capture Confirmation — deadlines confirmable, low confidence asks
- [x] Everything — Overdue / Today / Upcoming / No deadline / Completed / Archived
- [x] Task Detail — fields, actions, and Break it down
- [x] Focus — timer presets, Done / Pause / Stop
- [x] Completion — calm feedback, immediate recalculation
- [x] Rescue — all four paths
- [x] Minimum Win — planner built and Tier 1 tested
- [x] Settings — reminder controls and the cloud-processing consent switch
- [x] Dark mode — **shipped and measured** (D-027, corrected by D-029). One switch in Settings,
      light by default. `AppearanceUITests` drives the real control and reads the pixels: light
      0.808, dark on 0.119, dark off 0.808, and 0.119 again after a relaunch told nothing at all —
      run [31407733469](https://github.com/emoshansari-alt/NEXT/actions/runs/31407733469).
      The gate is gone. The four rounds that concluded it was applied to nothing had never flipped
      the switch — `toggle.tap()` does not work on a `Toggle` in a `Form`
- [x] Notifications — scheduling planned and Tier 1 tested
- [x] Daily replanning, no shame language — lateness decays rather than pinning a task to
      the screen for ever (D-020)
- [x] Minimum Win **surfaced in the UI** — offered on Today when the deadline is unreachable
- [x] "I'm stuck" reachable from inside Focus, and the smaller action replaces the current one
- [x] Notification deep link — tapping a reminder opens the task it named
- [ ] Notification delivery observed — needs a device, `RELEASE_GATED.md` B5
- [ ] Notification actions — deliberately out of 1.0 scope; §8 does not ask for them
- [ ] Widget with working deep link
- [ ] Paywall — invoked only by intent. **Built and Tier 2 verified, deliberately unreachable
      in a normal build** (D-015): NEXT+ unlocks nothing, so there is nothing to sell.
- [ ] **Decide the NEXT+ capability boundary, or strip the paywall — release blocking.**
      D-015 ships the machinery with `FeatureGate.oneDotZero` gating nothing. Either record the
      boundary as a decision entry and make the paywall reachable, or remove the screen. Shipping
      it reachable without that decision would put something on sale that grants nothing.
- [ ] Final NEXT+ pricing and purchase-option mix decided and justified (D-016 — the three
      products in the `.storekit` file are test fixtures, not a commitment)
- [ ] **Decide how an empty entitlement set is told apart from a genuine free tier (D-019).**
      A prerequisite of the boundary decision above, not a follow-up to it: the moment anything
      is gated, a subscriber whose entitlements come back empty gets sold what they already own.

### Engineering

- [x] `NextKit` has no forbidden import (CI-enforced)
- [x] No `Date()` or `UUID()` in `NextKit` (CI-enforced)
- [x] All scoring constants live in `ScoringWeights`
- [x] No stubbed ranking factor — `friction` is a decided zero (D-022)
- [x] No force unwraps outside tests — CI-enforced by `scripts/lint-shipped-code.sh`, verified
      against a deliberate violation probe. Also bans networking symbols and any external
      package (D-010) across all four shipped roots
- [x] No dead experiments or "temporary" hacks in shipped code
- [x] Release build succeeds at Tier 2 — app and widget, iOS Simulator, run [31340738838](https://github.com/emoshansari-alt/NEXT/actions/runs/31340738838). The first Release
      build in this repository's history
- [x] No compiler warnings in a clean build **of the shipped targets** — `NextApp`,
      `NextWidgetExtension` and the `NextKit` targets they pull in build Release at `-O` with
      `SWIFT_TREAT_WARNINGS_AS_ERRORS`, run [31340738838](https://github.com/emoshansari-alt/NEXT/actions/runs/31340738838), and Tier 1 builds with `-warnings-as-errors`.
      Narrowed to "shipped targets" on purpose: `GoldenPathUITests` still warns about
      main-actor isolation on XCTest's own `launch()`, which affects nothing that ships and is
      recorded in `TESTING.md` rather than folded into this tick

### Testing — see `TESTING.md` for what each tier proves

- [x] All Tier 1 unit tests pass — 559 in 100 suites
- [x] Every ranking edge case in `PRODUCT_SPEC.md` §5 covered — all eleven, with the three that
      were open closed this session: the deadline tier of the tie-break, a missing estimate's
      cost inside a stated window (D-025), and that the rejection penalty follows recency and
      never the tally
- [x] All eight AI failure-injection cases covered, none crash or corrupt data — both halves.
      Extended to the one write path that rewrites an *existing* task, which is the only place a
      bad response could damage work the user already had
- [x] Recommendation loop test passes — run as a loop: recommend, reject what came back,
      recommend again. The rejected task is taken from the engine's own first answer rather than
      named in the fixture
- [x] Tier 2 integration tests pass — 128 in 29 suites (2 known issues, both signing-gated), run [31367830604](https://github.com/emoshansari-alt/NEXT/actions/runs/31367830604)
- [x] Tier 2 golden-path UI test passes — 40 UI tests green, run [31367830604](https://github.com/emoshansari-alt/NEXT/actions/runs/31367830604). A 41st,
      `ScreenshotCaptureUITests`, is excluded by `-skip-testing` and runs in CI's own capture
      step, so it is not counted here
- [x] Offline behaviour proven at the tier that can prove it — see `TESTING.md`. No shipped
      source names a networking API (CI-enforced), and the whole loop runs green with the offline
      provider, run [31340738838](https://github.com/emoshansari-alt/NEXT/actions/runs/31340738838). The literal "with the network disabled" run is a Tier 3 device
      observation and stays in `RELEASE_GATED.md`: no XCUITest or `simctl` mechanism can turn a
      Simulator's networking off
- [x] Persistence survives the full create/terminate/relaunch/modify/complete cycle —
      Tier 2, run 31293153742, against a real on-disk store
- [x] Schema migration strategy exists and has a round-trip test — a real on-disk store closed
      and reopened through `NextMigrationPlan`, run [31340738838](https://github.com/emoshansari-alt/NEXT/actions/runs/31340738838), with a tripwire that fails the moment
      a second version is added without its own round trip

### Accessibility — release blocking

- [x] Every meaningful control has a useful label — audit-enforced
- [ ] VoiceOver traversal order is logical on every core screen
- [x] Dynamic Type works at the largest accessibility sizes without breaking layout —
      Today and Focus audited at accessibility XXXL
- [x] Reduce Motion respected — all four animation sites branch on it, where previously one did
      and `NextMotion.cardChange(reduceMotion:)` had no caller at all. Pinned by Tier 2 unit tests
      on the curves, including one that fails if the two curves are ever made equal, run [31340738838](https://github.com/emoshansari-alt/NEXT/actions/runs/31340738838)
- [x] The dark appearance is audited — Today empty, Today recommending, Rescue and Focus, driven
      by NEXT's own setting because `XCUIDevice.shared.appearance` has no effect on the runner.
      The screen is measured below 0.35 brightness *before* anything is audited, so an audit that
      quietly ran in light cannot pass. Contrast verdicts are checked against the element's own
      pixels (D-029)
- [x] Contrast adequate — enforced by the audit on every screen NEXT draws, and by
      `NextPaletteTests` on the values. One system-rendered section header per
      `List`/`Form` screen is tracked rather than enforced (D-021)
- [x] No meaning conveyed by colour alone — completion is spoken, not only struck through
- [x] No essential action is gesture-only — every swipe action has a button equivalent under
      test, and the deep-link task sheet has gained the Close button it never had: as the root of
      its own stack it had no back button, so it could only be left by swiping it away. Driven
      end to end by a UI test, run [31340738838](https://github.com/emoshansari-alt/NEXT/actions/runs/31340738838)
- [x] Touch targets meet current platform guidance — audit-enforced (D-021)
- [x] Errors announced accessibly — all seven failure surfaces announce on appearance. They were
      rendered only, and most sit *before* the control the user just operated in traversal order,
      so a refused permission left the toggle looking on and said nothing. When to speak is a
      tested pure function; whether VoiceOver actually spoke is device-only (B5)
- [x] Timer state accessible — spoken, not left to the digits
- [x] Decorative images hidden from assistive technology — no unlabelled symbol or image exists;
      the marker stripe declares itself hidden rather than relying on a modifier interaction; both
      spinners have labels, which they lacked for exactly as long as they were working. Capture
      Confirmation, which carries the app's only state-bearing symbol, is now audited too
- [x] Loading states understandable
- [ ] Two system-rendered exceptions — navigation-bar Dynamic Type and the first section
      header's contrast. Neither is app-fixable; both tracked under strict expected
      failures so they surface if SwiftUI changes (D-021)
- [ ] Remaining device-only checks explicitly listed in `RELEASE_GATED.md` B5

### Privacy and security

- [x] Data flows documented and current in `PRIVACY.md` — brought up to date against the code
      rather than the intended design, including the two flows added since it was written: a
      reminder's payload carries the task identifier it is about, and the widget reads a rendered
      snapshot from a shared container
- [x] No production secret in the binary or repository — there is none to ship, since nothing
      authenticates to anything, and CI fails on the shapes a credential takes
- [x] No task text in analytics, logs, or crash metadata — no analytics SDK exists (D-011), and
      NEXT keeps the stronger promise: **it logs nothing at all**, CI-enforced. That failure
      messages carry no task text is separately tested at Tier 1 (`IntelligencePrivacyTests`)
- [x] AI requests carry minimum necessary context only — Tier 1: no request type can hold a task
      identifier or a collection of anything, the rejection history never leaves, and extraction
      sends the typed text with no surrounding state
- [x] Cloud AI consent flow implemented, informed, and revocable — the switch exists, defaults
      off, is revocable, and its footer says plainly that nothing is sent today rather than
      implying a feature. Built before any cloud provider on purpose, so one cannot be added
      later without a consent gate already in front of it

### Performance

- [x] NEXT issues no network request at launch — no shipped source names a networking API at all
      (CI-enforced). Stated at this width deliberately: the one launch-time system integration is
      the StoreKit transaction listener, and whether Apple's out-of-process daemon contacts Apple
      is not something NEXT controls or can observe. The broader wording would have been false
- [x] No synchronous AI call at launch — no `IntelligenceProvider` is constructed anywhere in the
      launch graph, and both call sites are user-initiated and async
- [x] Cold start measured — **average 3.155 s over five launches** (2.31–4.30 s) on a GitHub
      macOS runner, run [31340738838](https://github.com/emoshansari-alt/NEXT/actions/runs/31340738838). Deliberately no asserted threshold: a limit invented here would be
      a number nobody chose, and a CI runner is slower and busier than any phone a student owns —
      the 24% relative standard deviation says so. "Acceptable" stays a judgement, now made
      against a recorded figure rather than against nothing
- [x] No unnecessary SDKs or oversized assets — zero third-party runtime dependencies (D-010,
      CI-enforced), and the entire shipped asset catalogue is one 1024 × 1024 app icon at 8.8 kB,
      generated from the palette's own hex values by a script rather than drawn

### Visual

**How visual work is decided (D-024).** Everything in this section is ordinary UI engineering and
is done autonomously. The items that stop for an owner proposal checkpoint are the subjective ones
— the app icon's *direction*, the palette and typography as a whole, marketing imagery, onboarding
artwork, and the App Store screenshot set below. D-024 lists them exhaustively and gives the
sequence.

- [x] No placeholder UI anywhere user-facing
- [x] App icon — the card, its spine and one marked line, rendered from the palette (D-023)
- [ ] Typography and hierarchy final — `NextType` is the scale and it is built from text styles,
      so everything scales with Dynamic Type. Narrowed from a tick: **about eighteen places
      across nine screens still name a system text style directly** rather than a `NextType`
      token. None writes a point size and none is an accessibility defect, but "one scale" is not
      yet literally true. A focused pass, not a bolt-on to another change
- [x] Motion restrained and Reduce-Motion-safe — one animated moment in the card, with a still
      equivalent that loses no information. **This line previously contradicted the Reduce Motion
      box above it**: press feedback and the onboarding page turn were two further animated
      moments and neither had a still equivalent. Both are guarded now, so one tick covers both
      lines honestly
- [ ] Haptics implemented (device verification remains gated)

### Documentation

- [x] `README.md`, `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `TESTING.md`,
      `PRIVACY.md`, `RELEASE_CHECKLIST.md`, `RELEASE_GATED.md` all current. A documentation audit
      in session 13 found four real gaps and all four are closed: `PRODUCT_SPEC.md` had no
      section for Settings at all and did not mention that NEXT has two appearances; its
      Everything section omitted Archived; `ARCHITECTURE.md` §6 described a Tier 2 that no longer
      matches CI; and D-023's promise that the icon "cannot drift" from the palette named a
      script that was never committed (**D-028** withdraws it)
- [x] `SESSION_LOG.md` current, with an exact next action — session 13
- [x] Known limitations explicitly documented — per session, in `SESSION_LOG.md`, and in the
      "not yet written" section of `TESTING.md`
- [x] Repository clean and fully committed

### Store preparation that needs no membership

- [ ] **Screenshot direction proposed and selected — owner checkpoint (D-024).** Two or three
      distinct presentation directions, shown as visual examples rather than described, with a
      recommendation. The set is not produced until a direction is selected. Other
      release-candidate work does not wait on this.
- [x] Screenshot narrative assembled — the six beats, fixed in `ScreenshotCaptureUITests`
- [x] Screenshots produced from the real app — six frames at 1320 × 2868, captured from the
      running app by `ScreenshotCaptureUITests` and exported by CI, and **composited into the
      Chroma layout** by `scripts/compose-store-screenshots.py`, run [31432584294](https://github.com/emoshansari-alt/NEXT/actions/runs/31432584294).
      The six ground colours in that script are a **reconstruction**: Chroma was selected in
      session 13 and its values were never committed, so they are the one part of the set worth a
      second opinion. The frames carry **no caption text**, because the listing wording is still
      an open decision on the line below and baking a draft of it into the images would take that
      decision on the way past
- [ ] Title, subtitle, description, keywords — **drafted** in `PRODUCT_SPEC.md` §15, with
      alternatives for the title and subtitle. The wording is chosen alongside the screenshot
      direction rather than separately (D-024): the two have to say the same thing in the same
      voice. Every claim in it is one the shipped app supports today
- [x] Privacy policy text drafted — `PRIVACY.md`, written for a sixteen-year-old to read in one
      go, because a policy nobody finishes is not consent. Every sentence is a claim the
      repository currently supports; it carries an instruction to re-check it against the code
      before publication, since the first cloud provider changes three of them
- [ ] Support contact decided — **owner decision.** It is the one placeholder in the drafted
      privacy policy and in `RELEASE_GATED.md` B3 that nobody else can supply
- [ ] Support contact decided
- [x] StoreKit product structure defined in a `.storekit` file — `NextApp/NEXT.storekit`,
      three provisional products, identifiers guarded by `scripts/lint-storekit.sh` (D-016)
- [x] App Store Connect configuration steps written out for later execution —
      `RELEASE_GATED.md` B3, in order, with the App Privacy answers derived from `PRIVACY.md`
      rather than left to be improvised under submission pressure. Names the two things that
      cannot be prepared yet, and why
- [x] Versioning and build-number strategy defined — D-026. Marketing version chosen by hand as
      `MAJOR.MINOR` starting at 1.0; build number derived from the commit count on `main`, so it
      is monotonic, unique, reproducible for a given commit, and never a field anyone forgets.
      Wiring it into `project.yml` belongs with the first archive, where it can be seen to work

---

## Part 2 — Apple-gated

Summarised only. The authoritative list is [`RELEASE_GATED.md`](RELEASE_GATED.md).

- **Gate A** — a macOS environment: compile the app, Simulator tests, a11y
  audit. *No paid membership required.* Planned via GitHub Actions.
- **Gate B** — paid membership: enrolment, signing, App Store Connect, production StoreKit,
  device verification, TestFlight, submission.

---

## Status vocabulary

Use exactly these terms:

- **In development** — building; not all Tier 1 tests pass.
- **Tier 1 verified** — `NextKit` fully tested; app layer never compiled.
- **Tier 2 verified** — app compiles, Simulator tests and a11y audit pass.
- **Local Release Candidate** — every Part 1 box ticked with evidence; only Gate B remains.
- **Released** — live on the App Store.

Today NEXT is: **Tier 2 verified.**

Corrected from "In development" in session 12, which had been wrong for several sessions rather
than modest: that term means "not all Tier 1 tests pass", and all 559 of them do. The app
compiles, the Simulator unit and UI suites pass, the accessibility audit passes on eleven screen
states, and a Release build of the app and widget now succeeds with warnings as errors — run
[31340738838](https://github.com/emoshansari-alt/NEXT/actions/runs/31340738838).

It is **not** a Local Release Candidate, and must not be called one: 18 Part 1 boxes are still
open. The largest are the NEXT+ capability boundary (D-015, D-016, D-019), the App Store
screenshot set, and the device-only checks in `RELEASE_GATED.md` B5.
