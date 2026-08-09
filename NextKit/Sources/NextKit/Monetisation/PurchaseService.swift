import Foundation

/// A product, as a screen needs to render it.
///
/// `displayPrice` is a **string the store handed over**, never a number NEXT formats. Currency
/// symbol placement, decimal separators, tax-inclusive display and the user's storefront are all
/// things Apple already knows and the app does not. An app that formats its own prices ends up
/// showing the wrong one to somebody.
public struct PurchasableProduct: Hashable, Sendable {

    public let id: ProductID
    public let kind: PurchaseKind

    /// The product's name, as configured in the store.
    public let displayName: String

    /// The localised price, exactly as the store phrased it.
    public let displayPrice: String

    public init(id: ProductID, kind: PurchaseKind, displayName: String, displayPrice: String) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.displayPrice = displayPrice
    }

    /// Whether this is the option NEXT leads with.
    public var isPrimary: Bool { id == NextPlusProducts.primary }
}

/// How an attempt to buy something ended.
///
/// Two of the three are not failures, and the type says so rather than leaving each caller to
/// decide. Modelling "the user changed their mind" or "a parent has to approve this" as errors
/// is how an app ends up showing a red banner to someone who did nothing wrong.
public enum PurchaseOutcome: Hashable, Sendable {

    /// Done, and this is what it granted.
    case purchased(EntitlementState)

    /// The person closed the sheet. Nothing to report and nothing to apologise for.
    case cancelled

    /// Waiting on someone else — Ask to Buy, or a bank confirmation.
    ///
    /// A normal path for an audience aged 16 to 22, not an edge case. The purchase may complete
    /// minutes or days later, so nothing should be presented as failed.
    case pendingApproval
}

/// Why a purchase could not be attempted or could not be trusted.
public enum PurchaseError: Error, Hashable, Sendable {

    /// The store does not have this product. In practice a configuration mistake, not a user one.
    case productUnavailable(ProductID)

    /// This device is not allowed to make purchases — parental controls, or a managed device.
    case notAllowed

    /// The store returned a transaction that failed verification.
    ///
    /// Unverified transactions are refused rather than trusted. A signature that does not check
    /// out is the one case where the safe answer is to grant nothing.
    case verificationFailed

    case networkUnavailable

    /// The App Store itself could not be reached or did not answer.
    case storeUnavailable
}

extension PurchaseError: LocalizedError {

    /// Wording is swept at Tier 1 for pressure and blame (`PRODUCT_SPEC.md` §3, invariant P5).
    /// A screen asking someone for money is where that temptation is strongest, and every one of
    /// these describes a situation the person reading it did not cause.
    public var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "That option is not available right now."
        case .notAllowed:
            return "Purchases are turned off on this device."
        case .verificationFailed:
            return "The App Store could not confirm that purchase, so nothing was changed."
        case .networkUnavailable:
            return "NEXT could not reach the App Store. Everything else keeps working offline."
        case .storeUnavailable:
            return "The App Store did not answer. Nothing was charged."
        }
    }
}

/// Buying NEXT+, behind a protocol so nothing above it needs StoreKit.
///
/// The same seam pattern as `TaskRepository` and `IntelligenceProvider`: `NextKit` owns the
/// protocol and the value types, `NextApp` owns the one implementation that imports StoreKit,
/// and `verifyPurchaseServiceContract(now:_:)` holds both to the identical promises.
///
/// **There is deliberately no stream of entitlement updates here.** StoreKit's transaction
/// listener is a real requirement, but it belongs inside the implementation: it refreshes what
/// `currentEntitlement()` reports, and a purchase already hands its result straight back from
/// `purchase(_:)`. Putting an `AsyncStream` in the protocol would add a shape every conforming
/// type and every test has to honour, in exchange for nothing any screen currently asks for.
public protocol PurchaseService: Sendable {

    /// The NEXT+ catalogue, primary option first.
    func products() async throws -> [PurchasableProduct]

    /// Attempts to buy one product.
    func purchase(_ id: ProductID) async throws -> PurchaseOutcome

    /// Re-reads what this Apple ID already owns.
    ///
    /// Required by App Review, and required by decency: someone who reinstalls the app must be
    /// able to get back what they paid for without paying again.
    func restore() async throws -> EntitlementState

    /// What the person is entitled to right now.
    func currentEntitlement() async throws -> EntitlementState
}
