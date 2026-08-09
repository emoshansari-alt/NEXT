# NEXT — Privacy and Data Flow

**Last updated:** 2026-08-09
**Status:** Architecture and policy, **current as of session 12 and verified against the code**
rather than describing an intended design. The public-facing privacy policy is drafted from this
document in Phase 15.

---

## Position

NEXT is local-first. Task data lives on the user's device. There is no account, no profile, and
no server holding the user's work.

The data NEXT handles is unusually sensitive for a productivity app: task titles reveal what a
student is studying, what they are behind on, and what they are avoiding. That is the reason
for the constraints below, not a generic compliance posture.

---

## What NEXT does not do

Categorically excluded from the product, not merely unimplemented:

- no user account, email, username, or profile
- no advertising identifier (IDFA) and no ad SDK
- no behavioural advertising
- no location collection of any kind
- no contact or calendar harvesting
- no public profiles, social graph, or sharing surface
- no selling, renting, or brokering of user data
- no analytics containing task text
- no crash report containing task text

---

## Data inventory

| Data | Where it lives | Leaves the device? | Why it exists |
|---|---|---|---|
| Task title, notes, deadline, duration, importance, status | On-device store | Only if the user invokes a cloud AI feature — see below | The product |
| Substeps and next actions | On-device store | Same | Rescue and Focus |
| Completion and rejection history | On-device store | Never | Ranking quality |
| Onboarding completion, settings | On-device preferences | Never | App behaviour |
| Purchase entitlement | Apple StoreKit | Handled by Apple | NEXT+ access |
| Notification content and schedule | iOS notification system, on device | Never | Reminders |
| The task identifier a reminder is about | The notification's own payload, on device | Never | Tapping a reminder opens that task rather than whatever Today happens to show |
| A rendered recommendation snapshot | A shared App Group container, on device | Never | The widget renders without opening the task store |

Two rows added in sessions 7–12 and worth being explicit about, because both put task text
somewhere other than the main store:

- **A reminder's text is a task title.** It is composed on the device, handed to iOS, and shown
  on the lock screen — which is the point of a reminder, and is the same exposure any calendar
  alert has. Nothing about it leaves the phone.
- **The widget snapshot is a few hundred bytes of JSON** holding the current recommendation's
  rendered strings. It exists so the widget never opens SwiftData, which also confined the App
  Group entitlement to the widget alone. It is written to a container shared between NEXT and its
  own extension, and by nothing else.

---

## AI data flow — the sensitive path

**Minimum necessary context.** An AI request carries only the text required for that one
operation. Breaking down one task sends that task — never the task list, never completion
history, never anything about other assignments.

**Explicitly forbidden in any request:** the full task database, completion history, rejection
history, device identifiers, or any stable user identifier.

**As built, no request goes anywhere.** The only provider NEXT ships is
`TemplateFallbackProvider`, which is deterministic, offline, and the default argument in both
view models that take a provider — so this is the shipping path, not a fallback from one. No
on-device model and no cloud model is wired up. The table below is therefore a description of
what each option *would* mean, and today only the third row is real.

Enforced, not just intended: `scripts/lint-shipped-code.sh` fails the build if any shipped
source names a networking API at all, across `NextKit`, the app and the widget. `URLSession`
comes from Foundation and needs no import, so before that lint existed adding one would have
passed every check in CI.

| Provider | Data leaves device | Consent |
|---|---|---|
| On-device model | No | Not required for processing; feature is still opt-in |
| Cloud model | Yes — the minimum context for that one call | Explicit, informed, revocable |
| Template fallback | No | None needed — no model involved |

**The consent switch exists and defaults to off.** It is in Settings, it is revocable at any
time, and its footer says plainly that NEXT currently reads notes entirely on the device and
that nothing written is sent anywhere — rather than implying a feature that does not exist. It
was built before any cloud provider on purpose, so that one cannot be added later without a
consent gate already standing in front of it.

**Consent is real consent.** Before any task text is sent off-device for the first time, the
user is told plainly what is sent, to whom, and why, and can decline. Declining leaves a fully
functional app: the deterministic engine, Focus, reminders and template-based Rescue all work
with no model at all (`PRODUCT_SPEC.md` §6).

Whether cloud AI ships in 1.0 at all is an open question, deferred to Phase 8 and recorded in
`DECISIONS.md` D-005.

---

## Analytics

No analytics SDK is integrated, and none is planned for 1.0 (`DECISIONS.md` D-011). There is no
third-party runtime dependency of any kind — enforced, since `scripts/lint-shipped-code.sh` also
fails on a `.package(` entry in `NextKit/Package.swift`.

If analytics are ever added they must be aggregate and content-free. The permitted event set is
exactly: `task_created`, `brain_dump_used`, `task_started`, `task_completed`, `rescue_used`,
`recommendation_rejected`.

Each event may carry only counts, coarse durations, and enum values. **No event may ever carry
task text, notes, titles, deadlines, or any free-form string derived from user content.**

Shipping with no third-party analytics is an acceptable and possibly preferred outcome. Crash
visibility is likely worth more, and is subject to the same rule: no task text may appear in a
crash report, breadcrumb, log line, or exception message.

---

## Logging

Task text must never be written to the system log, a crash breadcrumb, or an error message that
leaves the device.

**NEXT keeps the stronger version of that promise: it logs nothing at all.** There is no
`print`, `NSLog`, `os_log`, `Logger` or `dump` call anywhere in shipped code, so the question of
what a log line contains cannot arise — and `scripts/lint-shipped-code.sh` fails the build if one
appears. That is deliberately stricter than the rule above, because the realistic failure is not
a considered decision to log task text; it is a `print(task.title)` added while debugging and
left behind, which looks innocent in a diff.

The rule that failure *messages* carry no task text is separately tested at Tier 1: a validation
failure names the field and never the value, no failure case can hold free text at all, and a
provider failure never echoes the text it choked on (`IntelligencePrivacyTests`).

---

## Secrets

No production API key ships inside the app binary. There is none to ship — nothing authenticates
to anything — and `scripts/lint-shipped-code.sh` fails on the shapes a credential takes. A key in a distributed iOS app is
extractable and must be treated as public (`DECISIONS.md` D-009). If Phase 8 concludes that a
cloud model is genuinely required, a minimal token-broker service is designed and justified
then.

---

## Data lifetime and control

The user can delete any task, and deletion is real deletion from the local store — not a
hidden tombstone. Deleting the app removes all local task data with it. Because there is no
account and no server copy, there is no remote deletion request to make and nothing left behind.

---

## Apple App Privacy questionnaire — draft answers

To be finalised in Phase 15 once the Phase 8 provider decision is made. Current expected
answers:

| Category | Expected answer |
|---|---|
| Data used to track you | **None** |
| Data linked to you | **None** — there is no identity to link to |
| Data not linked to you | None today. If cloud AI ships: "User Content", used only for App Functionality, not linked to identity |
| Contact info, health, financial, location, browsing, identifiers | **Not collected** |

If cloud AI is *not* adopted in 1.0, NEXT expects to declare **no data collection at all**.
