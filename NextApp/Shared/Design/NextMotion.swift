import SwiftUI

/// Motion, kept deliberately scarce.
///
/// The Index Card direction would happily animate everything — cards invite it. The restraint is
/// borrowed from Margin (D-023): **one animated moment**, the one the product is about, and
/// nothing else moves. `NEXT → START → DONE → NEXT` is the loop `PRODUCT_SPEC.md` §10 says motion
/// should reinforce, so the card transition is where the whole budget is spent.
///
/// Reduce Motion is not a degraded path. Every animation here has a still equivalent that conveys
/// the same information, because §11 makes that release-blocking and because an app whose meaning
/// lives in movement is unusable to someone who has turned movement off.
enum NextMotion {

    /// The card leaving and the next one arriving.
    static let cardChange = Animation.spring(response: 0.34, dampingFraction: 0.82)

    /// A control acknowledging a finger.
    static let press = Animation.spring(response: 0.18, dampingFraction: 0.7)

    /// Everything else that must change visibly — a banner, a notice.
    static let quiet = Animation.easeOut(duration: 0.18)

    /// The still equivalent, used when Reduce Motion is on.
    static let reduced = Animation.easeOut(duration: 0.14)

    /// Picks the honest animation for the current setting.
    static func cardChange(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : cardChange
    }
}

/// How the recommendation replaces itself.
///
/// The finished card slides down and away; the next rises from beneath it. That direction is not
/// arbitrary — work leaves downward, the way a dealt card goes to the discard pile, and what is
/// next comes up from the deck.
struct CardTransition: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                )
        )
    }
}

extension View {

    /// Applies the one animated moment in the app.
    func cardTransition() -> some View {
        modifier(CardTransition())
    }
}
