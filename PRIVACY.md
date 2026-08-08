# NEXT — Privacy and Data Flow

**Last updated:** 2026-08-08
**Status:** Architecture and policy. The public-facing privacy policy is drafted from this
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
| Notification schedule | iOS notification system | Never | Reminders |

---

## AI data flow — the sensitive path

**Minimum necessary context.** An AI request carries only the text required for that one
operation. Breaking down one task sends that task — never the task list, never completion
history, never anything about other assignments.

**Explicitly forbidden in any request:** the full task database, completion history, rejection
history, device identifiers, or any stable user identifier.

Where the request goes depends on the provider selected in Phase 8:

| Provider | Data leaves device | Consent |
|---|---|---|
| On-device model | No | Not required for processing; feature is still opt-in |
| Cloud model | Yes — the minimum context for that one call | Explicit, informed, revocable |
| Template fallback | No | None needed — no model involved |

**Consent is real consent.** Before any task text is sent off-device for the first time, the
user is told plainly what is sent, to whom, and why, and can decline. Declining leaves a fully
functional app: the deterministic engine, Focus, reminders and template-based Rescue all work
with no model at all (`PRODUCT_SPEC.md` §6).

Whether cloud AI ships in 1.0 at all is an open question, deferred to Phase 8 and recorded in
`DECISIONS.md` D-005.

---

## Analytics

No analytics SDK is currently integrated (`DECISIONS.md` D-011).

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

Task text must never be written to the system log, a crash breadcrumb, or an error message
that leaves the device. Debug logging of task content is permitted only in `DEBUG` builds and
must be compiled out of release builds.

---

## Secrets

No production API key ships inside the app binary. A key in a distributed iOS app is
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
