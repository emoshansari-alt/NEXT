# NEXT — Release-Gated Work

Work here is blocked **only** by an external requirement — Apple Developer Program membership,
Mac hardware, or an Apple service. Nothing here is blocked by ordinary engineering effort.

**Ordinary unfinished coding work does not belong in this file.** It belongs in
[`SESSION_LOG.md`](SESSION_LOG.md).

**Last updated:** 2026-08-08

---

## Gate A — Mac hardware or a macOS CI runner

Blocks *compilation* of the app layer. This gate sits **before** the membership gate and is
independent of it.

| # | Item | Unblocked by | Status |
|---|------|--------------|--------|
| A1 | Compile `NextApp` (SwiftUI) | any macOS environment | **Not yet run** |
| A2 | Compile `NextWidget` (WidgetKit) | any macOS environment | **Not yet run** |
| A3 | Run iOS Simulator unit tests | any macOS environment | **Not yet run** |
| A4 | Run iOS Simulator UI tests (golden path) | any macOS environment | **Not yet run** |
| A5 | Local StoreKit `.storekit` entitlement testing | any macOS environment | **Not yet run** |
| A6 | Automated accessibility audit in Simulator | any macOS environment | **Not yet run** |
| A7 | Generate `.xcodeproj` from `project.yml` | any macOS environment + XcodeGen | **Not yet run** |

**This gate does not require paid membership.** Unsigned Simulator builds need no signing
certificate. It is satisfied by *either* a Mac *or* a GitHub Actions `macos-latest` runner,
which is free for public repositories and metered for private ones.

**Planned resolution:** GitHub Actions (Tier 2, `DECISIONS.md` D-001). Requires only a GitHub
repository — no Apple account, no payment.

---

## Gate B — Apple Developer Program membership (paid, ~US$99/year)

Blocks *distribution* and *device* work only.

### B1 — Enrolment

- [ ] Enrol in the Apple Developer Program
- [ ] Accept the Program License Agreement
- [ ] Complete banking and tax forms (required before any paid tier can be sold)

### B2 — Identifiers and signing

- [ ] Register the App ID / bundle identifier
- [ ] Create a development signing certificate
- [ ] Create a distribution signing certificate
- [ ] Create development and distribution provisioning profiles
- [ ] Register the App Group used to share task data with the widget
- [ ] Verify entitlements resolve against a real profile

### B3 — App Store Connect

- [ ] Create the app record
- [ ] Complete the App Privacy questionnaire (source: [`PRIVACY.md`](PRIVACY.md))
- [ ] Set age rating
- [ ] Upload icon, screenshots, description, keywords, support and privacy-policy URLs
- [ ] Host the privacy policy at a public URL

### B4 — StoreKit in production

- [ ] Create the real subscription group and NEXT+ products
- [ ] Set pricing in all territories
- [ ] Verify entitlement resolution against sandbox StoreKit — **not** the local `.storekit` file
- [ ] Test purchase, restore, cancellation, expiry, and refund handling in sandbox

Local `.storekit` testing (item A5) proves the app's own entitlement *logic*. It proves nothing
about App Store Connect configuration. These are different claims and must be reported as such.

### B5 — Physical device verification

Simulator cannot substitute for any of these:

- [ ] Real notification delivery and Notification Center behaviour
- [ ] Widget timeline refresh behaviour on a real home screen
- [ ] Haptics (Core Haptics is not available in Simulator)
- [ ] Real VoiceOver gesture navigation
- [ ] Real Dynamic Type at accessibility sizes
- [ ] Battery and thermal behaviour
- [ ] On-device intelligence availability on real hardware
- [ ] Performance on an older device representative of the target audience

### B6 — Distribution

- [ ] Archive and upload a build
- [ ] Internal TestFlight
- [ ] External TestFlight (requires Beta App Review)
- [ ] Submit for App Store review
- [ ] Respond to review feedback
- [ ] Release

---

## What is explicitly NOT blocked

To be clear about scope, none of the following is gated. All of it is ordinary work and none of
it may be deferred into this file:

product and architecture documentation · the entire `NextKit` domain layer · the deterministic
ranking engine · rescue logic · Minimum Win · time budgeting · AI response schema and validation
· the offline fallback provider · all `NextKit` unit tests · SwiftUI view authoring · widget
authoring · notification scheduling logic · StoreKit *client* architecture · the paywall ·
accessibility implementation · visual design · app icon and marketing assets · App Store copy ·
the privacy policy text · the release checklist.
