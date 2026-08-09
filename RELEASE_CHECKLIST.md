# NEXT — Release Checklist

Two lists. The first is work that must be finished **before** NEXT can be called a
**Local Release Candidate**. The second is everything gated on Apple, which lives in
[`RELEASE_GATED.md`](RELEASE_GATED.md) and is only summarised here.

**Last updated:** 2026-08-08

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
- [ ] Daily replanning, no shame language — engine recalculates, but no day-boundary behaviour
- [ ] Minimum Win **surfaced in the UI** — the planner has no caller yet
- [ ] "I'm stuck" reachable from inside Focus (currently Today only)
- [ ] Notification delivery observed, deep link, and actions
- [ ] Widget with working deep link
- [ ] Paywall — invoked only by intent. **Built and Tier 2 verified, deliberately unreachable
      in a normal build** (D-015): NEXT+ unlocks nothing, so there is nothing to sell.
- [ ] **Decide the NEXT+ capability boundary, or strip the paywall — release blocking.**
      D-015 ships the machinery with `FeatureGate.oneDotZero` gating nothing. Either record the
      boundary as a decision entry and make the paywall reachable, or remove the screen. Shipping
      it reachable without that decision would put something on sale that grants nothing.
- [ ] Final NEXT+ pricing and purchase-option mix decided and justified (D-016 — the three
      products in the `.storekit` file are test fixtures, not a commitment)

### Engineering

- [ ] `NextKit` has no forbidden import (CI-enforced)
- [ ] No `Date()` or `UUID()` in `NextKit` (CI-enforced)
- [ ] All scoring constants live in `ScoringWeights`
- [ ] No force unwraps outside tests
- [ ] No dead experiments or "temporary" hacks in shipped code
- [ ] Release build succeeds at Tier 2
- [ ] No compiler warnings in a clean build

### Testing — see `TESTING.md` for what each tier proves

- [ ] All Tier 1 unit tests pass
- [ ] Every ranking edge case in `PRODUCT_SPEC.md` §5 covered
- [ ] All eight AI failure-injection cases covered, none crash or corrupt data
- [ ] Recommendation loop test passes
- [ ] Tier 2 integration tests pass
- [ ] Tier 2 golden-path UI test passes
- [ ] Offline test passes
- [ ] Persistence survives the full create/terminate/relaunch/modify/complete cycle
- [ ] Schema migration strategy exists and has a round-trip test

### Accessibility — release blocking

- [ ] Every meaningful control has a useful label
- [ ] VoiceOver traversal order is logical on every core screen
- [ ] Dynamic Type works at the largest accessibility sizes without breaking layout
- [ ] Reduce Motion respected
- [ ] Contrast adequate throughout
- [ ] No meaning conveyed by colour alone
- [ ] No essential action is gesture-only
- [ ] Touch targets meet current platform guidance
- [ ] Errors announced accessibly
- [ ] Timer state accessible
- [ ] Decorative images hidden from assistive technology
- [ ] Loading states understandable
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

- [ ] No placeholder UI anywhere user-facing
- [ ] App icon final
- [ ] Typography and hierarchy final
- [ ] Motion restrained and Reduce-Motion-safe
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

- **Gate A** — a macOS environment: compile the app, Simulator tests, local StoreKit, a11y
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
