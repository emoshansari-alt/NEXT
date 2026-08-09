import SwiftUI

/// Spacing, radii and the card itself.
enum NextMetrics {

    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 13

    /// The ballpoint spine down the card's leading edge — the direction's only ornament.
    static let spineWidth: CGFloat = 4

    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 20

    /// How tall a block control should be.
    ///
    /// The comfortable 56 points is a *minimum* while the label is small. At an accessibility size
    /// the label is already taller than that, so the minimum stops being one and becomes padding —
    /// on Capture that pushed the save button above the keyboard and out of reach entirely, which
    /// the audit caught twice before this was fixed in one place rather than per screen.
    static func controlHeight(_ typeSize: DynamicTypeSize) -> CGFloat {
        typeSize.isAccessibilitySize ? 0 : tapTarget + 12
    }

    /// Minimum fingertip, per current platform guidance and enforced by the accessibility audit.
    ///
    /// Every button style here builds it in, which is why the standalone `accessibleTapTarget`
    /// modifier that Session 10 added is gone: a rule enforced by the only three controls the app
    /// has cannot be forgotten at a call site, whereas a modifier can.
    static let tapTarget: CGFloat = 44
}

/// The card. There is one on screen at a time, and that rule is the direction (D-023).
///
/// Not a general "card style" to be sprinkled about: a second card competing with the first is
/// exactly the clutter the product exists to remove, and the moment two appear the screen has
/// stopped answering "what is the one thing".
struct CardSurface: ViewModifier {

    /// Whether to draw the ballpoint spine. On for the recommendation; off for supporting cards
    /// such as Rescue's step, which is a smaller card and should not compete.
    var spine: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(NextMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: NextMetrics.cardRadius, style: .continuous)
                        .fill(NextPalette.card)

                    if spine {
                        Rectangle()
                            .fill(NextPalette.biro)
                            .frame(width: NextMetrics.spineWidth)
                    }
                }
                .clipShape(
                    RoundedRectangle(cornerRadius: NextMetrics.cardRadius, style: .continuous)
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: NextMetrics.cardRadius, style: .continuous)
                    .strokeBorder(NextPalette.edge, lineWidth: 0.5)
            )
            // Two layers rather than one: a tight contact shadow and a wide soft one. A single
            // blurred shadow reads as a drop-shadow effect; these two read as an object resting on
            // something, which is the entire point of the direction.
            .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(0.11), radius: 14, y: 8)
    }
}

extension View {

    /// Makes this the card. See `CardSurface` before adding a second one to any screen.
    func cardSurface(spine: Bool = true) -> some View {
        modifier(CardSurface(spine: spine))
    }

    /// The desk the card rests on.
    func deskBackground() -> some View {
        background(NextPalette.desk.ignoresSafeArea())
    }
}

extension View {

    /// Makes every row in a `List` or `Form` the card stock.
    ///
    /// Setting the scroll background to the desk is only half of it: rows keep the system's own
    /// background unless told otherwise, so ink chosen for contrast against the card ends up
    /// rendered against a colour nobody picked. The accessibility audit found that in bulk on
    /// Settings and Task Detail — eight and six issues respectively — and it is one line to fix.
    func listRowBackgroundIsCard() -> some View {
        listRowBackground(NextPalette.card)
    }
}
