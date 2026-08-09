import Foundation

/// What a person has paid for.
///
/// Two tiers, and deliberately no more. A third would need a reason to exist beyond the fact
/// that pricing pages usually have three columns.
public enum NextTier: String, Hashable, Sendable, Codable, CaseIterable {

    /// Everything NEXT does today. `PRODUCT_SPEC.md` §12 requires genuine value here — not a
    /// crippled demonstration of a paid app.
    case free

    /// NEXT+.
    case plus
}

/// What NEXT currently knows about the person's tier.
///
/// The third case is the one that matters. On launch StoreKit has not answered yet, and that is
/// **not** the same as knowing someone is on the free tier: a subscriber whose entitlement has
/// not loaded must never be shown a screen trying to sell them what they already bought.
/// Collapsing "not known yet" into "free" is the single most common way that bug ships.
public enum EntitlementStatus: Hashable, Sendable {

    /// The store has not answered yet.
    case unknown

    case free
    case plus

    /// The answer once the store has spoken.
    public init(tier: NextTier) {
        switch tier {
        case .free: self = .free
        case .plus: self = .plus
        }
    }

    public var isResolved: Bool { self != .unknown }
}
