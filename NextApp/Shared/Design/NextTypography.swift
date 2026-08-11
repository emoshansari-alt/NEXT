import SwiftUI

/// The type scale, and the reason `PRODUCT_SPEC.md` §10 says typography carries most of the
/// identity: on a card with one accent and no ornament, type is what is left to carry it.
///
/// Every role is built from a **text style**, never a fixed point size. A hard-coded 28 points
/// does not grow with Dynamic Type, and the audit is unforgiving about that — the largest
/// accessibility sizes are release-blocking (§11). Weight and tracking are what differentiate the
/// roles; size differences follow the system's scale.
enum NextType {

    /// The one thing to do. The largest thing on any screen, and usually the only large thing.
    static let action = Font.system(.largeTitle, design: .default, weight: .semibold)

    /// Focus shows the same action with the same face — the screen changes, the sentence does not.
    static let actionFocused = Font.system(.largeTitle, design: .default, weight: .bold)

    /// The task an action belongs to, when naming it adds something.
    static let parent = Font.system(.subheadline, design: .default, weight: .regular)

    /// Section titles and the headline of an empty state.
    static let heading = Font.system(.title3, design: .default, weight: .semibold)

    /// Ordinary body copy — settings rows, explanations, notes.
    static let body = Font.system(.body)

    /// Buttons.
    static let control = Font.system(.headline, design: .default, weight: .semibold)

    /// Secondary controls: quieter, but the same face.
    static let controlSecondary = Font.system(.subheadline, design: .default, weight: .medium)

    /// Durations, dates, counts, countdowns. Monospaced so digits do not jitter as they change,
    /// which on a running timer is the difference between a clock and a fidget.
    static let meta = Font.system(.footnote, design: .monospaced)

    /// A supporting note: a failure, a notice, or a line of status, almost always in
    /// `inkSecondary`. Quieter than `body` and never the reason a screen exists.
    ///
    /// The same size as `meta` and proportional rather than monospaced, which is the whole
    /// distinction between them. `meta` exists so a changing number does not jitter; a sentence
    /// has no digits to hold still and reads better set proportionally.
    ///
    /// Defined from what the nine sites it replaced were already doing — `Font.system(.footnote)`
    /// is `Font.footnote` — so this named a role that existed rather than changing one. Nothing
    /// rendered differently the day it landed, which is the point: a consolidation that moves
    /// pixels is a redesign wearing a refactor's clothes.
    static let note = Font.system(.footnote)

    /// The countdown itself.
    static let timer = Font.system(.largeTitle, design: .monospaced, weight: .medium)

    /// `NEXT` above the card, and the only tracked-out type in the app.
    ///
    /// The same mark appears on the card, in the widget and on the icon. One repeated mark is
    /// cheaper than a logo and harder to get wrong.
    static let eyebrow = Font.system(.caption2, design: .monospaced, weight: .semibold)

    // MARK: - What this scale does not name
    //
    // A pass in session 14 audited every `.font(…)` in the app and the widget against these
    // tokens. Four sites were token misuse and were converted; a fifth role — `note` above — was
    // missing and was added with the owner's approval, closing nine sites. The rest are **not**
    // misuse: they are roles this scale has no name for, and inventing names for them is a change
    // to the design language rather than an implementation detail (D-024), so they are listed
    // rather than absorbed.
    //
    // - **A small annotation.** `.caption` on Capture Confirmation's "Is this right?" and "No
    //   deadline", `.caption2` on the paywall's badge.
    // - **Emphasis inside body copy.** Minimum Win's rung goal, body at medium weight.
    // - **Onboarding's own scale.** A large-title headline and a title3 body, on full-screen
    //   panels with no card. Onboarding is the one screen that is not the index card, so it may
    //   legitimately sit outside a scale built for one.
    // - **The action, at widget scale.** `NextWidget` draws the same thing the card calls
    //   `action`, at a size a widget can hold. It already uses `meta` and `parent`; what it
    //   lacks is a smaller `action`, not a general headline.
    //
    // Nothing above is an accessibility defect. Every one is built from a text style and scales
    // with Dynamic Type; the only fixed point size in the repository is `AppearanceProbe`'s
    // two-point invisible label, which is test-only and never rendered for a user.
}

extension View {

    /// The eyebrow's full treatment, so the tracking is not re-typed at each site.
    func nextEyebrow() -> some View {
        font(NextType.eyebrow)
            .tracking(2.2)
            .textCase(.uppercase)
            .foregroundStyle(NextPalette.inkSecondary)
    }
}
