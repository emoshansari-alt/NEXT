# NEXT — Release-Gated Work

Work here is blocked **only** by an external requirement — Apple Developer Program membership,
Mac hardware, or an Apple service. Nothing here is blocked by ordinary engineering effort.

**Ordinary unfinished coding work does not belong in this file.** It belongs in
[`SESSION_LOG.md`](SESSION_LOG.md).

**Last updated:** 2026-08-08

---

## Gate A — a macOS build environment — **RESOLVED 2026-08-08**

This gate blocked *compilation* of the app layer and sat before the membership gate. It is now
closed and **nothing in it is gated any more.**

**Resolution.** The repository is public at `emoshansari-alt/NEXT`, and
`.github/workflows/ci.yml` runs on GitHub Actions `macos-latest`, where standard runners are
free for public repositories. No Apple Developer Program membership was needed — Simulator
builds are unsigned.

**Evidence.** CI run
[31253999769](https://github.com/emoshansari-alt/NEXT/actions/runs/31253999769), 2026-08-08:
all three jobs green. Tier 1 ran on the macOS runner with Apple Swift 6.3.3 and passed 16 of
16 tests. The Tier 2 job executed and correctly reported that `project.yml` does not exist yet.

**What this means for the items formerly listed here.** Compiling `NextApp` and `NextWidget`,
Simulator unit and UI tests, local StoreKit testing, the accessibility audit, and generating
the `.xcodeproj` are now **ordinary unfinished work, not gated work.** They are tracked in
[`SESSION_LOG.md`](SESSION_LOG.md) and [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md), and have
been removed from this file per its own rule: only genuinely externally-blocked items belong
here.

`NextApp` and `NextWidget` remain **UNVERIFIED** — but because they do not exist yet, not
because they cannot be built.

---

## Gate B — Apple Developer Program membership (paid, ~US$99/year)

Blocks *distribution* and *device* work only.

### B1 — Enrolment

- [ ] Enrol in the Apple Developer Program
- [ ] Accept the Program License Agreement
- [ ] Complete banking and tax forms (required before any paid tier can be sold)

### B1a — App Group, and therefore the widget — **measured, not assumed**

- [ ] Provision the `group.com.nextapp.next` App Group
- [ ] Verify the widget reads the snapshot the app writes
- [ ] Verify the widget's home-screen timeline refresh on a real device

**Evidence.** CI run
[31285133615](https://github.com/emoshansari-alt/NEXT/actions/runs/31285133615), 2026-08-09.
A Tier 2 test asserted that `containerURL(forSecurityApplicationGroupIdentifier:)` resolves.
It does not: in an unsigned Simulator build the call returns `nil`, because App Groups are
*provisioned* entitlements and no profile grants one. Declaring the entitlement in
`project.yml` is not sufficient.

**What still works without it.** Everything except the widget's content. The widget target
compiles, installs and renders; it shows its "Open NEXT to see what is next." placeholder
because there is no snapshot to read. `SnapshotStore` returns `nil` and writes are no-ops, so
the app itself is entirely unaffected — a Tier 2 test pins that degradation explicitly.

**What is verified without signing:** snapshot construction, staleness, JSON round-tripping,
deep-link generation and parsing, and that the app survives an unavailable container. Only the
app-to-widget handoff is gated.

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
