# NEXT — Release-Gated Work

Work here is blocked **only** by an external requirement — Apple Developer Program membership,
Mac hardware, or an Apple service. Nothing here is blocked by ordinary engineering effort.

**Ordinary unfinished coding work does not belong in this file.** It belongs in
[`SESSION_LOG.md`](SESSION_LOG.md).

**Last updated:** 2026-08-09

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
Simulator unit and UI tests, the accessibility audit, and generating
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

#### The steps in order, written out now so they are not improvised later

Written while the reasoning behind each answer is still fresh, which is the point: the App
Privacy questionnaire in particular is a set of legal declarations, and the honest answers are
the ones derivable from `PRIVACY.md` rather than the ones that seem safe under time pressure.

1. **Create the app record.** Bundle identifier `com.nextapp.next` — it must match `project.yml`
   exactly, and it cannot be changed after the first upload. Primary language English (UK),
   category Productivity.
2. **Answer the App Privacy questionnaire from `PRIVACY.md`, not from memory.** As NEXT is built
   today the answer to every collection question is **no**: no account, no analytics SDK, no
   third-party dependency, no networking of any kind, no advertising identifier. The expected
   declaration is therefore **"Data Not Collected"** in full. That answer stops being true the
   moment a cloud provider ships, which is why `PRIVACY.md` says so in the same place.
3. **Age rating.** No objectionable content, no user-generated content shown to other users, no
   web view, no gambling, no unrestricted web access — the questionnaire should come out at 4+.
   NEXT's audience is 16–22 but the rating describes content, not target audience.
4. **Encryption declaration.** `ITSAppUsesNonExemptEncryption` is already `false` in
   `NextApp/Info.plist`, which is correct: NEXT ships no encryption of its own and makes no
   network request. This is what stops every upload asking the same question again.
5. **Support URL and privacy-policy URL.** Both must be public and reachable at submission. The
   privacy policy text is drafted from `PRIVACY.md`; the support contact is an owner decision and
   is the one item here nobody else can make.
6. **Upload the build**, then attach screenshots, description and keywords. Screenshots have
   their own approval sequence — see D-024 — and must be produced from the real app.
7. **TestFlight before submission**, which is also the first opportunity to close B5's device
   checks: notification delivery, real VoiceOver traversal, real haptics, and the widget's
   content.

Two things are deliberately *not* on this list, because they would be guesses. The NEXT+ products
cannot be created in App Store Connect until D-015's capability boundary and D-016's pricing are
decided — creating them earlier would put identifiers on record that the decision might change.
And no submission can be prepared while `FeatureGate.oneDotZero` gates nothing, because the
paywall would be selling something that grants nothing.

### B4a — Local StoreKit testing — **measured, not assumed**

- [ ] Verify the NEXT+ catalogue resolves against a `.storekit` configuration
- [ ] Verify a purchase completes and grants the entitlement end to end
- [ ] Verify expiry, billing retry and refund against `SKTestSession`'s own controls

**Evidence.** CI runs
[31288009406](https://github.com/emoshansari-alt/NEXT/actions/runs/31288009406),
[31288499393](https://github.com/emoshansari-alt/NEXT/actions/runs/31288499393) and
[31289011381](https://github.com/emoshansari-alt/NEXT/actions/runs/31289011381), 2026-08-09.

`ARCHITECTURE.md` §6 and D-001 both list "local StoreKit testing" as a Tier 2 capability needing
no membership. **That turns out to be wrong**, and the correction is recorded here rather than
quietly dropped. Both documented routes were measured:

1. **`SKTestSession(configurationFileNamed:)`** with the configuration in the test bundle. A
   diagnostic run confirmed the file is present and found at
   `NextAppTests.xctest/NEXT.storekit`, and the session object is created — but every operation
   on it fails with `SKInternalErrorDomain` Code 3:

   ```
   [SKTestSession] Error saving configuration file: Error Domain=SKInternalErrorDomain Code=3
   [SKTestSession] Error deleting all transactions: Error Domain=SKInternalErrorDomain Code=3
   ```

2. **The scheme's StoreKit configuration**, set on the run and test actions in `project.yml`.
   Identical result: `Product.products(for:)` returns an empty array.

`clearTransactions()` never reads the configuration file, so an error deleting transactions
cannot be explained by the file's contents. The StoreKit test facility is refusing the process
itself — the same shape of answer as the App Group in B1a, and for the same underlying reason:
the build is unsigned and carries no entitlements.

**What still works without it.** Everything except talking to a store. Every entitlement rule —
tier resolution, the expiry boundary, bounded billing-retry grace, per-receipt revocation, the
capability gate — is proven at Tier 1 on Windows and does not involve Apple at all. The paywall,
its copy, the view model's failure handling and its refusal to claim a failed lookup means "free"
are all Tier 2 verified against a stub. Two UI tests verify that a normal build cannot reach the
paywall and that the screen behind the flag works. A Tier 2 test pins the degradation: with no
store to talk to, the catalogue is empty, nothing is falsely claimed as owned, and buying throws
rather than silently doing nothing.

**What is gated:** that a real purchase completes, that a real receipt maps into
`EntitlementRecord` as expected, and that a real expiry or refund revokes access. Those are the
claims the contract test makes and cannot currently run — it is marked `withKnownIssue`, so it
starts running for free the day signing exists rather than needing to be remembered.

### B4 — StoreKit in production

- [ ] Create the real subscription group and NEXT+ products
- [ ] Set pricing in all territories
- [ ] Verify entitlement resolution against sandbox StoreKit — **not** the local `.storekit` file
- [ ] Test purchase, restore, cancellation, expiry, and refund handling in sandbox

Local `.storekit` testing (B4a) would prove the app's own entitlement *plumbing*. It proves
nothing about App Store Connect configuration, and it is itself not currently runnable. These are
three different claims — the rules, the plumbing, the store's configuration — and each must be
reported as such rather than folded into "purchases work".

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
