import Foundation
import StoreKit
import StoreKitTest
import Testing

@testable import NextApp
import NextKit
import NextKitTestSupport

private struct FixedTimeSource: TimeSource {
    let now: Date
}

// MARK: - The experiment
//
// Whether local StoreKit testing can be driven from an unsigned Simulator build under
// `xcodebuild` was genuinely unknown when this was written — the same shape of question the App
// Group turned out to answer with a flat no (RELEASE_GATED.md B1a). So it is asserted rather than
// assumed, and CI is what answers it.
//
// The route taken is `SKTestSession`, which loads the .storekit configuration from the test
// bundle. It needs no scheme configuration and no signing, which is precisely why it was chosen
// over the scheme's StoreKit Configuration option.

@Suite("StoreKit — the purchase contract against a real store", .serialized)
struct StoreKitPurchaseServiceTests {

    private func session() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "NEXT")
        // Without this the purchase sheet appears and a unit test has no way to dismiss it.
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    @Test("the StoreKit-backed service honours the identical contract the stub does")
    func storeKitHonoursTheContract() async throws {
        let session = try session()
        defer { session.clearTransactions() }

        // The same function Tier 1 runs against a stub. Neither tier re-derives the rules, so
        // they cannot drift — the arrangement that has already paid for itself with the storage
        // contract.
        try await verifyPurchaseServiceContract(now: Date()) {
            session.clearTransactions()
            return StoreKitPurchaseService()
        }
    }

    @Test("the catalogue carries the store's own prices rather than any NEXT invented")
    func pricesComeFromTheStore() async throws {
        let session = try session()
        defer { session.clearTransactions() }

        let products = try await StoreKitPurchaseService().products()

        #expect(products.count == 3)
        for product in products {
            // Not asserting the amounts. They are provisional (DECISIONS.md D-016) and a test
            // that pins them would have to be edited every time the owner changes their mind,
            // which is not what this is verifying. That the string came from StoreKit is.
            #expect(product.displayPrice.isEmpty == false)
            #expect(product.displayPrice.contains("$") || product.displayPrice.contains("."))
        }
    }

    @Test("a subscription that runs out takes NEXT+ with it")
    func expiredSubscriptionEndsAccess() async throws {
        // The entitlement rules are proven at Tier 1 against plain values. This asks a different
        // question: that a real expiry, produced by StoreKit rather than by a fixture, arrives in
        // the shape those rules expect.
        let session = try session()
        defer { session.clearTransactions() }

        let service = StoreKitPurchaseService()
        _ = try await service.purchase(NextPlusProducts.annual)
        #expect(try await service.currentEntitlement().tier(at: Date()) == .plus)

        try session.expireSubscription(productIdentifier: NextPlusProducts.annual.rawValue)

        #expect(try await service.currentEntitlement().tier(at: Date()) == .free)
    }
}

// MARK: - A store that answers however a test needs

private actor StubPurchaseService: PurchaseService {

    enum Behaviour: Sendable {
        case succeed
        case cancel
        case awaitApproval
        case fail(PurchaseError)
    }

    private var behaviour: Behaviour
    private var entitlement: EntitlementState
    private let catalogue: [PurchasableProduct]

    init(
        behaviour: Behaviour = .succeed,
        entitlement: EntitlementState = .none,
        catalogue: [PurchasableProduct]? = nil
    ) {
        self.behaviour = behaviour
        self.entitlement = entitlement
        self.catalogue = catalogue ?? NextPlusProducts.all.map { id in
            PurchasableProduct(
                id: id,
                kind: NextPlusProducts.kind(of: id) ?? .lifetime,
                displayName: "NEXT+",
                displayPrice: "$0.00"
            )
        }
    }

    func products() async throws -> [PurchasableProduct] {
        if case .fail(let error) = behaviour { throw error }
        return catalogue
    }

    func purchase(_ id: ProductID) async throws -> PurchaseOutcome {
        switch behaviour {
        case .fail(let error): throw error
        case .cancel: return .cancelled
        case .awaitApproval: return .pendingApproval
        case .succeed:
            entitlement = EntitlementState(isLifetime: true)
            return .purchased(entitlement)
        }
    }

    func restore() async throws -> EntitlementState {
        if case .fail(let error) = behaviour { throw error }
        return entitlement
    }

    func currentEntitlement() async throws -> EntitlementState {
        if case .fail(let error) = behaviour { throw error }
        return entitlement
    }
}

@MainActor
@Suite("PaywallViewModel")
struct PaywallViewModelTests {

    private let now = Date(timeIntervalSince1970: 1_773_133_200)  // 2026-03-10 09:00 UTC

    private func model(_ service: any PurchaseService) -> PaywallViewModel {
        PaywallViewModel(service: service, timeSource: FixedTimeSource(now: now))
    }

    @Test("loading shows the catalogue and the current tier")
    func loadPopulatesTheScreen() async {
        let paywall = model(StubPurchaseService())

        await paywall.load()

        #expect(paywall.products.count == 3)
        #expect(paywall.status == .free)
        #expect(paywall.notice == nil)
    }

    @Test("a store that cannot be reached leaves the tier unknown, never free")
    func failureDoesNotClaimTheUserIsFree() async {
        // The bug this exists to prevent: a subscriber opens NEXT+, the store times out, and the
        // app decides they are on the free tier and tries to sell them what they already own.
        // "Not known" and "not entitled" are different answers and must stay different.
        let paywall = model(StubPurchaseService(behaviour: .fail(.networkUnavailable)))

        await paywall.load()

        #expect(paywall.status == .unknown)
        #expect(paywall.isPlus == false)
        #expect(paywall.notice == PurchaseError.networkUnavailable.errorDescription)
    }

    @Test("a completed purchase switches NEXT+ on and says so")
    func purchaseSwitchesItOn() async {
        let paywall = model(StubPurchaseService())
        await paywall.load()

        await paywall.buy(NextPlusProducts.annual)

        #expect(paywall.status == .plus)
        #expect(paywall.isPlus)
        #expect(paywall.notice == NextPlusCopy.purchased)
    }

    @Test("closing the purchase sheet says nothing at all")
    func cancellingIsSilent() async {
        // Reporting "cancelled" back to the person who cancelled is the app narrating their own
        // decision to them.
        let paywall = model(StubPurchaseService(behaviour: .cancel))
        await paywall.load()

        await paywall.buy(NextPlusProducts.annual)

        #expect(paywall.notice == nil)
        #expect(paywall.status == .free)
    }

    @Test("waiting for approval is explained, not reported as a failure")
    func pendingIsExplained() async {
        let paywall = model(StubPurchaseService(behaviour: .awaitApproval))
        await paywall.load()

        await paywall.buy(NextPlusProducts.monthly)

        #expect(paywall.notice == NextPlusCopy.pending)
        #expect(paywall.status == .free)
    }

    @Test("restoring nothing says so plainly instead of looking broken")
    func restoringNothingIsAnAnswer() async {
        let paywall = model(StubPurchaseService(behaviour: .cancel))
        await paywall.load()

        await paywall.restore()

        #expect(paywall.notice == NextPlusCopy.restoredNothing)
    }

    @Test("restoring an existing purchase brings it back")
    func restoringSomethingWorks() async {
        let owned = StubPurchaseService(entitlement: EntitlementState(isLifetime: true))
        let paywall = model(owned)

        await paywall.restore()

        #expect(paywall.isPlus)
        #expect(paywall.notice == NextPlusCopy.restoredSomething)
    }
}

@Suite("Paywall copy")
struct PaywallCopyTests {

    @Test("the paywall advertises nothing while nothing is behind it")
    func nothingIsAdvertisedWhileNothingIsGated() {
        // Tied to the gate table on purpose, so the two cannot drift. Selling a benefit that
        // `FeatureGate` does not actually gate would be a false claim, and it is the kind that
        // gets written by accident when a pricing page is drafted before the boundary is decided.
        let gatesSomething = PremiumCapability.allCases.contains {
            FeatureGate.oneDotZero.requiredTier(for: $0) == .plus
        }

        if gatesSomething {
            #expect(
                NextPlusCopy.benefits.isEmpty == false,
                "something is now behind the paywall and the screen says nothing about it"
            )
        } else {
            #expect(
                NextPlusCopy.benefits.isEmpty,
                "the paywall lists a benefit while every capability is free"
            )
        }
    }

    @Test("no line on the paywall pressures the person reading it")
    func copyIsFreeOfPressure() {
        let forbidden = [
            "miss you", "don't forget", "hurry", "act now", "last chance",
            "limited time", "you're behind", "falling behind", "only today", "!"
        ]

        var lines = [
            NextPlusCopy.title,
            NextPlusCopy.nothingIsGatedYet,
            NextPlusCopy.restore,
            NextPlusCopy.restoredNothing,
            NextPlusCopy.restoredSomething,
            NextPlusCopy.purchased,
            NextPlusCopy.pending,
            NextPlusCopy.primaryBadge
        ]
        lines.append(contentsOf: PurchaseKind.allCases.map { NextPlusCopy.period(for: $0) })

        for line in lines {
            for phrase in forbidden {
                #expect(
                    line.lowercased().contains(phrase) == false,
                    "\"\(line)\" says \"\(phrase)\""
                )
            }
        }
    }

    @Test("the recommended option is named without inventing a saving")
    func noFabricatedDiscount() {
        // Working out "save 30%" across localised prices and currencies is arithmetic the client
        // will eventually get wrong for somebody. The badge recommends; the store prices.
        let badge = NextPlusCopy.primaryBadge.lowercased()

        #expect(badge.contains("%") == false)
        #expect(badge.contains("save") == false)
        #expect(badge.contains("off") == false)
    }
}

@Suite("Where the paywall can be reached from")
struct MonetisationAvailabilityTests {

    @Test("a normal launch cannot reach the paywall")
    func paywallIsUnreachableByDefault() {
        // The unit test target launches the app without the flag, so this is the production
        // answer. NEXT+ unlocks nothing today, and a way in would be offering to sell it
        // (DECISIONS.md D-015).
        #expect(MonetisationAvailability.isPaywallReachable == false)
    }

    @Test("the launch argument is the only way in")
    func theFlagIsTheSwitch() {
        #expect(MonetisationAvailability.testingArgument == "-storekit-testing")
    }
}
