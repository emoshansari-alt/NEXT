import Foundation
import Testing

@testable import NextKit
import NextKitTestSupport

// MARK: - A store that never talks to Apple
//
// Enough of a purchase service to hold the contract to account at Tier 1. It is an actor because
// buying something mutates state and the protocol is `Sendable`; nothing here is a mock of
// StoreKit's shape, only of its answers.

private actor StubPurchaseService: PurchaseService {

    /// What the next `purchase(_:)` should do. Buying is the one operation with several
    /// legitimate non-error outcomes, and each of them needs exercising.
    enum Response: Sendable {
        case succeed
        case cancel
        case awaitApproval
    }

    private let now: Date
    private var records: [EntitlementRecord] = []
    private var response: Response = .succeed

    init(now: Date) {
        self.now = now
    }

    func setResponse(_ response: Response) {
        self.response = response
    }

    func products() async throws -> [PurchasableProduct] {
        NextPlusProducts.all.map { id in
            PurchasableProduct(
                id: id,
                kind: NextPlusProducts.kind(of: id) ?? .lifetime,
                displayName: "NEXT+",
                displayPrice: "$0.00"
            )
        }
    }

    func purchase(_ id: ProductID) async throws -> PurchaseOutcome {
        guard let kind = NextPlusProducts.kind(of: id) else {
            throw PurchaseError.productUnavailable(id)
        }

        switch response {
        case .cancel:
            return .cancelled
        case .awaitApproval:
            return .pendingApproval
        case .succeed:
            records.append(
                EntitlementRecord(
                    productID: id,
                    purchaseDate: now,
                    expirationDate: kind.expiry(from: now),
                    isInBillingRetry: false,
                    revocationDate: nil
                )
            )
            return .purchased(EntitlementResolver.resolve(records))
        }
    }

    func restore() async throws -> EntitlementState {
        EntitlementResolver.resolve(records)
    }

    func currentEntitlement() async throws -> EntitlementState {
        EntitlementResolver.resolve(records)
    }
}

private extension PurchaseKind {
    /// When a period bought at `start` runs out. Approximate on purpose — the real dates come
    /// from Apple, and this only has to be far enough away to be unambiguously live.
    func expiry(from start: Date) -> Date? {
        switch self {
        case .monthly: return start.addingTimeInterval(30 * 24 * 3600)
        case .annual: return start.addingTimeInterval(365 * 24 * 3600)
        case .lifetime: return nil
        }
    }
}

// MARK: - Tests

@Suite("PurchaseService — the contract")
struct PurchaseServiceContractTests {

    @Test("a store that never talks to Apple honours the whole contract")
    func stubHonoursTheContract() async throws {
        // The identical function runs at Tier 2 against real StoreKit. Whether it can is the open
        // question this phase set out to answer; either way the rules are written once.
        try await verifyPurchaseServiceContract(now: .testReference) {
            StubPurchaseService(now: .testReference)
        }
    }
}

@Suite("PurchaseService — outcomes that are not failures")
struct PurchaseOutcomeTests {

    @Test("changing your mind is an outcome, not an error")
    func cancellationIsNotAnError() async throws {
        let store = StubPurchaseService(now: .testReference)
        await store.setResponse(.cancel)

        let outcome = try await store.purchase(NextPlusProducts.annual)

        #expect(outcome == .cancelled)
        #expect(try await store.currentEntitlement().tier(at: .testReference) == .free)
    }

    @Test("waiting for a parent to approve is an outcome, not an error")
    func pendingApprovalIsNotAnError() async throws {
        // Ask to Buy is a normal path for an audience aged 16 to 22, not an edge case. Treating
        // it as a failure would tell a student their purchase broke when it is simply waiting.
        let store = StubPurchaseService(now: .testReference)
        await store.setResponse(.awaitApproval)

        let outcome = try await store.purchase(NextPlusProducts.monthly)

        #expect(outcome == .pendingApproval)
        #expect(try await store.currentEntitlement().tier(at: .testReference) == .free)
    }

    @Test("a completed purchase reports the entitlement it granted")
    func purchaseCarriesItsEntitlement() async throws {
        let store = StubPurchaseService(now: .testReference)

        let outcome = try await store.purchase(NextPlusProducts.lifetime)

        guard case .purchased(let state) = outcome else {
            Issue.record("expected a completed purchase, got \(outcome)")
            return
        }
        #expect(state.isLifetime)
        #expect(state.tier(at: .testReference) == .plus)
    }
}

@Suite("NEXT+ products")
struct NextPlusProductTests {

    @Test("the catalogue is the three products the .storekit file defines")
    func catalogueIsComplete() {
        #expect(Set(NextPlusProducts.all) == [
            NextPlusProducts.monthly,
            NextPlusProducts.annual,
            NextPlusProducts.lifetime
        ])
    }

    @Test("annual leads, because it is the option NEXT actually recommends")
    func annualIsPrimary() {
        #expect(NextPlusProducts.primary == NextPlusProducts.annual)
        #expect(NextPlusProducts.all.first == NextPlusProducts.annual)
    }

    @Test("every product identifier maps to a kind")
    func everyProductHasAKind() {
        for id in NextPlusProducts.all {
            #expect(NextPlusProducts.kind(of: id) != nil, "\(id) has no kind")
        }
    }

    @Test("an identifier NEXT does not sell has no kind")
    func unknownProductHasNoKind() {
        #expect(NextPlusProducts.kind(of: ProductID("com.nextapp.next.plus.imaginary")) == nil)
    }

    @Test("only the lifetime product is a one-off")
    func onlyLifetimeIsNonRecurring() {
        #expect(NextPlusProducts.kind(of: NextPlusProducts.lifetime) == .lifetime)
        #expect(NextPlusProducts.kind(of: NextPlusProducts.annual)?.isRecurring == true)
        #expect(NextPlusProducts.kind(of: NextPlusProducts.monthly)?.isRecurring == true)
    }
}

@Suite("Monetisation tone")
struct MonetisationToneTests {

    /// The same sweep the reminder copy gets. A screen that is asking for money is exactly where
    /// pressure would be most tempting and least acceptable (PRODUCT_SPEC.md §3, invariant P5).
    private static let forbidden = [
        "miss you", "don't forget", "hurry", "act now", "last chance", "limited time",
        "you're behind", "falling behind", "only today", "!"
    ]

    @Test("no purchase failure blames or pressures the person reading it")
    func purchaseErrorsAreNeutral() {
        let errors: [PurchaseError] = [
            .productUnavailable(NextPlusProducts.annual),
            .notAllowed,
            .verificationFailed,
            .networkUnavailable,
            .storeUnavailable
        ]

        for error in errors {
            let text = (error.errorDescription ?? "").lowercased()
            #expect(text.isEmpty == false, "\(error) has no description")

            for phrase in Self.forbidden {
                #expect(
                    text.contains(phrase) == false,
                    "\(error) says \"\(phrase)\""
                )
            }
        }
    }

    @Test("a failed purchase never suggests the user did something wrong")
    func purchaseErrorsDoNotAccuse() {
        // A payment failing is almost never the user's doing, and being told it is lands badly on
        // someone who was trying to give you money.
        let accusatory = ["you failed", "your mistake", "invalid", "denied"]

        for error in [PurchaseError.notAllowed, .verificationFailed] {
            let text = (error.errorDescription ?? "").lowercased()
            for phrase in accusatory {
                #expect(text.contains(phrase) == false, "\(error) says \"\(phrase)\"")
            }
        }
    }
}
