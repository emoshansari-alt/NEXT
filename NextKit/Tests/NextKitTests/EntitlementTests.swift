import Foundation
import Testing

@testable import NextKit

/// What NEXT+ access means, decided as pure arithmetic over an injected instant.
///
/// Nothing here knows what StoreKit is. The app converts whatever StoreKit reports into
/// `EntitlementRecord` values — a mechanical mapping with no rules in it — and every rule that
/// decides whether someone is a paying user lives here, where it runs on Windows in
/// milliseconds instead of on a Simulator in ten minutes.
@Suite("Entitlement — what NEXT+ access means")
struct EntitlementTests {

    @Test("someone who has bought nothing is on the free tier")
    func noPurchasesIsFree() {
        #expect(EntitlementState.none.tier(at: .testReference) == .free)
    }

    @Test("a lifetime purchase is NEXT+ regardless of dates")
    func lifetimeIsPlus() {
        let state = EntitlementState(isLifetime: true)

        #expect(state.tier(at: .testReference) == .plus)
        #expect(state.tier(at: .daysFromReference(3650)) == .plus)
    }

    @Test("a subscription that has not run out is NEXT+")
    func liveSubscriptionIsPlus() {
        let state = EntitlementState(subscriptionExpiry: .daysFromReference(20))

        #expect(state.tier(at: .testReference) == .plus)
    }

    @Test("a subscription that has run out is back on the free tier")
    func expiredSubscriptionIsFree() {
        let state = EntitlementState(subscriptionExpiry: .daysFromReference(-1))

        #expect(state.tier(at: .testReference) == .free)
    }

    @Test("the expiry instant itself has expired")
    func expiryBoundaryIsExclusive() {
        // Stated as a rule rather than left to whichever comparison got typed first. Access runs
        // up to the expiry instant and not through it, which is what Apple's expirationDate means.
        let expiry = Date.daysFromReference(30)
        let state = EntitlementState(subscriptionExpiry: expiry)

        #expect(state.tier(at: expiry.addingTimeInterval(-1)) == .plus)
        #expect(state.tier(at: expiry) == .free)
    }

    @Test("a declined card keeps access while Apple is still retrying it")
    func billingRetryKeepsAccess() {
        // Apple retries a failed renewal for weeks. Cutting a paying student off the moment their
        // bank hiccups is the punishment P4 and P5 forbid, and they have done nothing wrong —
        // most of these retries succeed.
        let state = EntitlementState(
            subscriptionExpiry: .daysFromReference(-2),
            isInBillingRetry: true
        )

        #expect(state.tier(at: .testReference) == .plus)
    }

    @Test("billing retry does not keep access forever")
    func billingRetryIsBounded() {
        // The generous reading of a declined card is bounded, or a stuck flag becomes a permanent
        // free subscription. Apple's own retry window is the bound.
        let expiry = Date.daysFromReference(-1)
        let state = EntitlementState(subscriptionExpiry: expiry, isInBillingRetry: true)

        let insideGrace = expiry.addingTimeInterval(EntitlementState.billingRetryGrace - 3600)
        let pastGrace = expiry.addingTimeInterval(EntitlementState.billingRetryGrace + 3600)

        #expect(state.tier(at: insideGrace) == .plus)
        #expect(state.tier(at: pastGrace) == .free)
    }

    @Test("billing retry on its own grants nothing")
    func billingRetryNeedsASubscription() {
        // There is nothing to extend if no period was ever paid for.
        let state = EntitlementState(isInBillingRetry: true)

        #expect(state.tier(at: .testReference) == .free)
    }
}

/// Turning what the store reports into what the user is owed.
@Suite("EntitlementResolver — reading the receipts")
struct EntitlementResolverTests {

    private func subscription(
        _ id: ProductID = NextPlusProducts.annual,
        expires: Date?,
        retrying: Bool = false,
        revoked: Date? = nil
    ) -> EntitlementRecord {
        EntitlementRecord(
            productID: id,
            purchaseDate: .testReference,
            expirationDate: expires,
            isInBillingRetry: retrying,
            revocationDate: revoked
        )
    }

    @Test("no receipts means no entitlement")
    func nothingResolvesToNothing() {
        #expect(EntitlementResolver.resolve([]) == .none)
    }

    @Test("a purchase with no expiry is the lifetime product")
    func absentExpiryMeansLifetime() {
        let state = EntitlementResolver.resolve([
            subscription(NextPlusProducts.lifetime, expires: nil)
        ])

        #expect(state.isLifetime)
        #expect(state.tier(at: .testReference) == .plus)
    }

    @Test("a refunded purchase grants nothing")
    func revokedRecordsAreIgnored() {
        let state = EntitlementResolver.resolve([
            subscription(expires: .daysFromReference(300), revoked: .testReference)
        ])

        #expect(state == .none)
        #expect(state.tier(at: .testReference) == .free)
    }

    @Test("refunding the subscription does not take away a lifetime purchase")
    func revocationIsPerReceipt() {
        // The reason revocation is modelled per receipt rather than as one flag on the whole
        // account. Someone who subscribed, refunded it, and later bought Lifetime still owns
        // Lifetime, and a single revoked flag would have quietly taken it away.
        let state = EntitlementResolver.resolve([
            subscription(expires: .daysFromReference(300), revoked: .testReference),
            subscription(NextPlusProducts.lifetime, expires: nil)
        ])

        #expect(state.isLifetime)
        #expect(state.tier(at: .testReference) == .plus)
    }

    @Test("the furthest expiry wins when more than one period is on file")
    func latestExpiryWins() {
        let state = EntitlementResolver.resolve([
            subscription(NextPlusProducts.monthly, expires: .daysFromReference(5)),
            subscription(NextPlusProducts.annual, expires: .daysFromReference(200))
        ])

        #expect(state.subscriptionExpiry == .daysFromReference(200))
    }

    @Test("a revoked receipt cannot be the one that sets the expiry")
    func revokedExpiryIsNotCounted() {
        let state = EntitlementResolver.resolve([
            subscription(NextPlusProducts.monthly, expires: .daysFromReference(5)),
            subscription(
                NextPlusProducts.annual,
                expires: .daysFromReference(200),
                revoked: .testReference
            )
        ])

        #expect(state.subscriptionExpiry == .daysFromReference(5))
    }

    @Test("a receipt in billing retry is carried through")
    func billingRetryIsCarried() {
        let state = EntitlementResolver.resolve([
            subscription(expires: .daysFromReference(-1), retrying: true)
        ])

        #expect(state.isInBillingRetry)
        #expect(state.tier(at: .testReference) == .plus)
    }

    @Test("a revoked receipt cannot smuggle in a grace period")
    func revokedRetryIsIgnored() {
        let state = EntitlementResolver.resolve([
            subscription(expires: .daysFromReference(-1), retrying: true, revoked: .testReference)
        ])

        #expect(state.isInBillingRetry == false)
        #expect(state.tier(at: .testReference) == .free)
    }
}
