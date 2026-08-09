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

    /// The countdown itself.
    static let timer = Font.system(.largeTitle, design: .monospaced, weight: .medium)

    /// `NEXT` above the card, and the only tracked-out type in the app.
    ///
    /// The same mark appears on the card, in the widget and on the icon. One repeated mark is
    /// cheaper than a logo and harder to get wrong.
    static let eyebrow = Font.system(.caption2, design: .monospaced, weight: .semibold)
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
