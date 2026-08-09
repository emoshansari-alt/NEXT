import Foundation

/// One purchase, as neutral data.
///
/// `NextKit` cannot import StoreKit (DECISIONS.md D-002), and that constraint turns out to be
/// the right shape anyway: the app converts each StoreKit transaction into one of these — a
/// mechanical field-for-field mapping with no decisions in it — and every *rule* about what a
/// purchase entitles someone to lives in `EntitlementResolver`, where it is proven at Tier 1.
///
/// The alternative, asking StoreKit questions at the point of use, would put the rules somewhere
/// only a Simulator can reach them.
public struct EntitlementRecord: Hashable, Sendable {

    public let productID: ProductID

    public let purchaseDate: Date

    /// When this period runs out, or `nil` for a one-off purchase that never does.
    public let expirationDate: Date?

    /// Apple is retrying a payment that was declined.
    public let isInBillingRetry: Bool

    /// When this purchase was refunded or revoked, if it was.
    ///
    /// Per record rather than per account on purpose — see `EntitlementResolver`.
    public let revocationDate: Date?

    public init(
        productID: ProductID,
        purchaseDate: Date,
        expirationDate: Date?,
        isInBillingRetry: Bool = false,
        revocationDate: Date? = nil
    ) {
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.isInBillingRetry = isInBillingRetry
        self.revocationDate = revocationDate
    }
}

/// What someone is entitled to, reduced to the three facts that decide it.
///
/// Deliberately not a copy of the receipts. Everything a screen needs to ask — am I paying, when
/// does it run out, is a payment being retried — is answerable from here, and nothing else about
/// a purchase is any of the app's business.
public struct EntitlementState: Hashable, Sendable, Codable {

    /// How long access survives a declined payment.
    ///
    /// Apple retries a failed renewal for weeks, and most of those retries succeed. Revoking
    /// access the instant a card bounces punishes someone who has done nothing wrong and, in
    /// most cases, is about to pay. It is bounded rather than open-ended so that a flag left
    /// stuck true cannot quietly become a permanent free subscription.
    public static let billingRetryGrace: TimeInterval = 16 * 24 * 3600

    /// A one-off purchase that does not expire.
    public var isLifetime: Bool

    /// When the paid period runs out, if there is one.
    public var subscriptionExpiry: Date?

    /// Apple is retrying a declined renewal.
    public var isInBillingRetry: Bool

    public init(
        isLifetime: Bool = false,
        subscriptionExpiry: Date? = nil,
        isInBillingRetry: Bool = false
    ) {
        self.isLifetime = isLifetime
        self.subscriptionExpiry = subscriptionExpiry
        self.isInBillingRetry = isInBillingRetry
    }

    /// Someone who has bought nothing.
    public static let none = EntitlementState()

    /// The tier this state grants at a given instant.
    ///
    /// Access runs up to the expiry instant and not through it, which is what Apple's
    /// `expirationDate` means. Stated as a test rather than left to whichever comparison
    /// happened to get typed.
    public func tier(at now: Date) -> NextTier {
        if isLifetime { return .plus }

        guard let subscriptionExpiry else { return .free }

        if now < subscriptionExpiry { return .plus }

        if isInBillingRetry,
           now < subscriptionExpiry.addingTimeInterval(Self.billingRetryGrace) {
            return .plus
        }

        return .free
    }

    public func status(at now: Date) -> EntitlementStatus {
        EntitlementStatus(tier: tier(at: now))
    }
}

/// Turns a pile of receipts into one answer.
public enum EntitlementResolver {

    /// Reduces every purchase on file to a single entitlement.
    ///
    /// **Revocation is honoured per record, not per account.** Someone who subscribed, refunded
    /// that subscription, and later bought Lifetime still owns Lifetime; a single "was revoked"
    /// flag on the account would have silently taken it away from them. That is the whole reason
    /// this is a reduction over records rather than a few booleans maintained by the app.
    ///
    /// Where receipts disagree the most generous one wins — the furthest expiry, and lifetime
    /// over any period. Someone holding two overlapping receipts has, if anything, paid twice.
    public static func resolve(_ records: [EntitlementRecord]) -> EntitlementState {
        var state = EntitlementState.none

        for record in records where record.revocationDate == nil {
            guard let expiry = record.expirationDate else {
                state.isLifetime = true
                continue
            }

            if let known = state.subscriptionExpiry, known >= expiry { continue }

            state.subscriptionExpiry = expiry
            state.isInBillingRetry = record.isInBillingRetry
        }

        return state
    }
}
