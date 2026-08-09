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
- [x] Not this — rejection with reasons and a temporary penalty
- [x] Why this? — deterministic explanation, works offline
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
- [ ] Release build succeeds at Tier 2 — a Release build of the app and widget now runs in CI
- [ ] No compiler warnings in a clean build — Tier 1 builds with `-warnings-as-errors` and the
      Tier 2 Release build with `SWIFT_TREAT_WARNINGS_AS_ERRORS`. Tier 1 measured clean; the app
      layer's warning count had never been measured by anyone and is now gated rather than
      asserted

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
- [x] Tier 2 integration tests pass — 103 in 24 suites
- [x] Tier 2 golden-path UI test passes
- [ ] Offline behaviour proven at the tier that can prove it — see `TESTING.md`. The literal
      "with the network disabled" run is a Tier 3 device observation and lives in
      `RELEASE_GATED.md`; what is provable here is that no shipped source names a networking API
      (CI-enforced) and that the whole loop runs with no provider answering
- [x] Persistence survives the full create/terminate/relaunch/modify/complete cycle —
      Tier 2, run 31293153742, against a real on-disk store
- [ ] Schema migration strategy exists and has a round-trip test — written: a real on-disk store
      closed and reopened through `NextMigrationPlan`, with a tripwire that fails the moment a
      second version is added without its own round trip

### Accessibility — release blocking

- [x] Every meaningful control has a useful label — audit-enforced
- [ ] VoiceOver traversal order is logical on every core screen
- [x] Dynamic Type works at the largest accessibility sizes without breaking layout —
      Today and Focus audited at accessibility XXXL
- [ ] Reduce Motion respected — all four animation sites now branch on it, where previously one
      did and `NextMotion.cardChange(reduceMotion:)` had no caller at all. Pinned by Tier 2 unit
      tests on the curves, because no audit category can see motion
- [x] Contrast adequate — enforced by the audit on every screen NEXT draws, and by
      `NextPaletteTests` on the values. One system-rendered section header per
      `List`/`Form` screen is tracked rather than enforced (D-021)
- [x] No meaning conveyed by colour alone — completion is spoken, not only struck through
- [ ] No essential action is gesture-only — every swipe action has a button equivalent under
      test, and the deep-link task sheet has gained the Close button it never had: as the root of
      its own stack it had no back button, so it could only be left by swiping it away
- [x] Touch targets meet current platform guidance — audit-enforced (D-021)
- [ ] Errors announced accessibly — all seven failure surfaces now announce on appearance. They
      were rendered only, and most sit *before* the control the user just operated in traversal
      order, so a refused permission left the toggle looking on and said nothing
- [x] Timer state accessible — spoken, not left to the digits
- [ ] Decorative images hidden from assistive technology — no unlabelled symbol or image exists;
      the marker stripe now declares itself hidden rather than relying on a modifier interaction;
      both spinners have labels, which they lacked for exactly as long as they were working
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
- [ ] Cold start measured and acceptable — `testColdStartIsMeasured` records the figure at
      Tier 2 with `XCTApplicationLaunchMetric`. Deliberately no asserted threshold: a limit
      invented here would be a number nobody chose, and a GitHub macOS runner is slower and
      busier than any phone a student owns. "Acceptable" stays a judgement, made against a
      recorded figure rather than against nothing
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

- [ ] `README.md`, `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `TESTING.md`,
      `PRIVACY.md`, `RELEASE_CHECKLIST.md`, `RELEASE_GATED.md` all current
- [ ] `SESSION_LOG.md` current, with an exact next action
- [ ] Known limitations explicitly documented
- [ ] Repository clean and fully committed

### Store preparation that needs no membership

- [ ] **Screenshot direction proposed and selected — owner checkpoint (D-024).** Two or three
      distinct presentation directions, shown as visual examples rather than described, with a
      recommendation. The set is not produced until a direction is selected. Other
      release-candidate work does not wait on this.
- [ ] Screenshot narrative assembled
- [ ] Screenshots produced from the real app — the real NEXT interface is the source of truth;
      generated imagery may support the composition but may not fabricate functionality or stand
      in for a screenshot (D-014, D-024)
- [ ] Title, subtitle, description, keywords drafted
- [ ] Privacy policy text drafted
- [ ] Support contact decided
- [x] StoreKit product structure defined in a `.storekit` file — `NextApp/NEXT.storekit`,
      three provisional products, identifiers guarded by `scripts/lint-storekit.sh` (D-016)
- [ ] App Store Connect configuration steps written out for later execution
- [ ] Versioning and build-number strategy defined

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

Today NEXT is: **In development.**
