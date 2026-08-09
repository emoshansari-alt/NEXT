import Foundation
import NextKit

/// Every word the paywall says.
///
/// Kept together, and swept by a test, for the same reason the reminder copy is: a screen asking
/// someone for money is where pressure is most tempting and least acceptable (`PRODUCT_SPEC.md`
/// §3 and §12, invariant P5). No countdown, no scarcity, no invented saving.
enum NextPlusCopy {

    static let title = "NEXT+"

    /// What NEXT+ unlocks.
    ///
    /// **Empty, and that is the honest answer today.** Every capability NEXT has is free
    /// (`FeatureGate.oneDotZero`), so there is nothing to list, and listing something anyway
    /// would be selling a promise. `PaywallCopyTests` ties this to the gate table directly: while
    /// the table gates nothing, this must stay empty. When the NEXT+ boundary is decided
    /// (DECISIONS.md D-015), both change together or the test fails.
    static let benefits: [String] = []

    /// Shown in place of the benefits while there are none.
    static let nothingIsGatedYet = """
        Everything in NEXT is free, and nothing you already use will move behind a payment. \
        NEXT+ has no features of its own yet.
        """

    static let restore = "Restore purchases"

    static let restoredNothing = "No previous purchase found on this Apple ID."

    static let restoredSomething = "Restored. NEXT+ is on."

    static let purchased = "Thank you. NEXT+ is on."

    /// Ask to Buy, or a bank confirmation. Not a failure, and not phrased as one.
    static let pending = """
        Waiting for approval. Nothing has been charged, and NEXT+ will switch on by itself if \
        it comes through.
        """

    /// The recommended option, said plainly.
    ///
    /// No percentage. Working out a saving across localised prices and currencies is arithmetic
    /// the client will eventually get wrong for somebody, and the App Store already shows people
    /// what things cost.
    static let primaryBadge = "Recommended"

    /// A one-line description per product kind.
    static func period(for kind: PurchaseKind) -> String {
        switch kind {
        case .monthly: return "Billed monthly. Cancel any time."
        case .annual: return "Billed once a year. Cancel any time."
        case .lifetime: return "One payment. No subscription."
        }
    }
}
