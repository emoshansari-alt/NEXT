import Foundation

/// A product identifier as App Store Connect and the local `.storekit` file spell it.
public struct ProductID: Hashable, Sendable, Codable {

    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension ProductID: CustomStringConvertible {
    public var description: String { rawValue }
}

/// What kind of thing a product is.
public enum PurchaseKind: String, Hashable, Sendable, Codable, CaseIterable {

    case monthly
    case annual

    /// A one-off purchase that never expires.
    case lifetime

    /// Whether this one bills again.
    public var isRecurring: Bool { self != .lifetime }
}

/// The NEXT+ catalogue.
///
/// These identifiers are the single source of truth. The `.storekit` configuration file spells
/// the same three strings, and `scripts/lint-storekit.sh` fails the build if the two ever
/// disagree — a typo in a product identifier is otherwise invisible until a real purchase does
/// not resolve, which is the worst possible moment to find it.
///
/// **The products are provisional.** Their existence exercises the three distinct entitlement
/// paths — a short renewing period, a long renewing period, and a purchase that never expires —
/// and is not a decision that all three will ship, nor at these prices (DECISIONS.md D-016).
public enum NextPlusProducts {

    public static let monthly = ProductID("com.nextapp.next.plus.monthly")
    public static let annual = ProductID("com.nextapp.next.plus.annual")
    public static let lifetime = ProductID("com.nextapp.next.plus.lifetime")

    /// The option NEXT recommends, and therefore the one shown first.
    ///
    /// Recommended plainly, with its real price beside the others. No countdown, no invented
    /// percentage saved — cross-currency arithmetic on top of localised prices is a lie waiting
    /// to be shipped, and the App Store already shows people what things cost.
    public static let primary = annual

    /// Every product, primary first.
    public static let all: [ProductID] = [annual, monthly, lifetime]

    /// What a product identifier is, or `nil` if NEXT does not sell it.
    ///
    /// Returning `nil` rather than guessing matters: an unrecognised identifier reaching the
    /// purchase path is a bug, and treating it as a subscription would hide it.
    public static func kind(of id: ProductID) -> PurchaseKind? {
        switch id {
        case monthly: return .monthly
        case annual: return .annual
        case lifetime: return .lifetime
        default: return nil
        }
    }
}
