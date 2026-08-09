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
- [ ] No force unwraps outside tests
- [x] No dead experiments or "temporary" hacks in shipped code
- [ ] Release build succeeds at Tier 2
- [ ] No compiler warnings in a clean build

### Testing — see `TESTING.md` for what each tier proves

- [x] All Tier 1 unit tests pass — 549 in 100 suites
- [ ] Every ranking edge case in `PRODUCT_SPEC.md` §5 covered
- [ ] All eight AI failure-injection cases covered, none crash or corrupt data
- [ ] Recommendation loop test passes
- [x] Tier 2 integration tests pass — 103 in 24 suites
- [x] Tier 2 golden-path UI test passes
- [ ] Offline test passes
- [x] Persistence survives the full create/terminate/relaunch/modify/complete cycle —
      Tier 2, run 31293153742, against a real on-disk store
- [ ] Schema migration strategy exists and has a round-trip test

### Accessibility — release blocking

- [x] Every meaningful control has a useful label — audit-enforced
- [ ] VoiceOver traversal order is logical on every core screen
- [x] Dynamic Type works at the largest accessibility sizes without breaking layout —
      Today and Focus audited at accessibility XXXL
- [ ] Reduce Motion respected
- [x] Contrast adequate — enforced by the audit on every screen NEXT draws, and by
      `NextPaletteTests` on the values. One system-rendered section header per
      `List`/`Form` screen is tracked rather than enforced (D-021)
- [x] No meaning conveyed by colour alone — completion is spoken, not only struck through
- [ ] No essential action is gesture-only
- [x] Touch targets meet current platform guidance — audit-enforced (D-021)
- [ ] Errors announced accessibly
- [x] Timer state accessible — spoken, not left to the digits
- [ ] Decorative images hidden from assistive technology
- [x] Loading states understandable
- [ ] Two system-rendered exceptions — navigation-bar Dynamic Type and the first section
      header's contrast. Neither is app-fixable; both tracked under strict expected
      failures so they surface if SwiftUI changes (D-021)
- [ ] Remaining device-only checks explicitly listed in `RELEASE_GATED.md` B5

### Privacy and security

- [ ] Data flows documented and current in `PRIVACY.md`
- [ ] No production secret in the binary or repository
- [ ] No task text in analytics, logs, or crash metadata
- [ ] AI requests carry minimum necessary context only
- [ ] Cloud AI consent flow implemented, informed, and revocable

### Performance

- [ ] No network request at launch
- [ ] No synchronous AI call at launch
- [ ] Cold start measured and acceptable
- [ ] No unnecessary SDKs or oversized assets

### Visual

- [x] No placeholder UI anywhere user-facing
- [x] App icon — the card, its spine and one marked line, rendered from the palette (D-023)
- [x] Typography and hierarchy final — one scale in `NextType`, built from text styles so it
      scales with Dynamic Type
- [x] Motion restrained and Reduce-Motion-safe — one animated moment, with a still
      equivalent that loses no information
- [ ] Haptics implemented (device verification remains gated)

### Documentation

- [ ] `README.md`, `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `TESTING.md`,
      `PRIVACY.md`, `RELEASE_CHECKLIST.md`, `RELEASE_GATED.md` all current
- [ ] `SESSION_LOG.md` current, with an exact next action
- [ ] Known limitations explicitly documented
- [ ] Repository clean and fully committed

### Store preparation that needs no membership

- [ ] Screenshots produced from the real app
- [ ] Screenshot narrative assembled
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
