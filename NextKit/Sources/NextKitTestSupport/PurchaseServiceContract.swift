import Foundation
import NextKit

/// The `PurchaseService` contract, as an executable specification.
///
/// Same reasoning as `verifyRepositoryContract(_:)`, and the same construction: a library rather
/// than test-target code, throwing rather than using `#expect`, because the implementation that
/// matters most — the StoreKit-backed one in `NextApp` — cannot be compiled on the Windows
/// development machine at all. Tier 1 runs this against a stub; Tier 2 runs the identical
/// function against real StoreKit under a test session.
///
/// Whether Tier 2 *can* run it was an open question when this was written. If it turns out that
/// local StoreKit testing needs something an unsigned Simulator build does not have, this file
/// does not change — the answer gets recorded in `RELEASE_GATED.md` alongside the App Group
/// finding, and Tier 1 keeps proving every rule that does not require Apple.

/// A promise the store did not keep.
public struct PurchaseContractViolation: Error, CustomStringConvertible {

    public let requirement: String
    public let detail: String

    public var description: String {
        "PurchaseService contract violated — \(requirement). \(detail)"
    }
}

private func requirePurchase(
    _ condition: Bool,
    _ requirement: String,
    _ detail: String = ""
) throws {
    guard !condition else { return }
    throw PurchaseContractViolation(requirement: requirement, detail: detail)
}

/// Runs every promise `PurchaseService` makes against one implementation.
///
/// `make` must hand back a service with **no purchases on file**. Every section asks for its own,
/// so a purchase made by one cannot leak into another — at Tier 2 that means clearing the test
/// session's transactions, which is exactly the kind of setup a shared contract should not know
/// about and therefore does not.
///
/// `now` is a parameter rather than a clock read, because `NextKit/Sources` may not call `Date()`
/// (DECISIONS.md D-007) and this file lives there. Tier 1 passes its fixed reference instant;
/// Tier 2 passes the real one, since a subscription bought a moment ago expires relative to it.
public func verifyPurchaseServiceContract(
    now: Date,
    _ make: @Sendable () async throws -> any PurchaseService
) async throws {
    try await verifyCatalogue(make())
    try await verifyNothingIsOwnedInitially(make(), now: now)
    try await verifyBuyingASubscription(make(), now: now)
    try await verifyBuyingLifetime(make(), now: now)
    try await verifyUnsellableProduct(make())
}

/// What is on sale, and how it is described.
private func verifyCatalogue(_ service: any PurchaseService) async throws {
    let products = try await service.products()

    try requirePurchase(
        Set(products.map(\.id)) == Set(NextPlusProducts.all),
        "the catalogue is exactly the NEXT+ products",
        "got \(products.map(\.id.rawValue))"
    )

    try requirePurchase(
        products.first?.id == NextPlusProducts.primary,
        "the recommended option is listed first",
        "first was \(String(describing: products.first?.id))"
    )

    for product in products {
        try requirePurchase(
            product.displayName.isEmpty == false,
            "every product has a name",
            "\(product.id) has none"
        )
        // The price must come from the store. An empty one means the client would have to invent
        // it, and an invented price is the one thing a paywall may never show.
        try requirePurchase(
            product.displayPrice.isEmpty == false,
            "every product carries the store's own localised price",
            "\(product.id) has none"
        )
        try requirePurchase(
            NextPlusProducts.kind(of: product.id) == product.kind,
            "a product's kind matches the catalogue",
            "\(product.id) claims \(product.kind)"
        )
    }

    try requirePurchase(
        products.filter(\.isPrimary).count == 1,
        "exactly one option is the recommended one",
        "\(products.filter(\.isPrimary).count) claim to be"
    )
}

/// A fresh Apple ID owns nothing, and that is an ordinary state rather than an error.
private func verifyNothingIsOwnedInitially(
    _ service: any PurchaseService,
    now: Date
) async throws {
    let entitlement = try await service.currentEntitlement()

    try requirePurchase(
        entitlement.tier(at: now) == .free,
        "someone who has bought nothing is on the free tier",
        "got \(entitlement)"
    )

    let restored = try await service.restore()
    try requirePurchase(
        restored.tier(at: now) == .free,
        "restoring nothing reports nothing rather than failing",
        "got \(restored)"
    )
}

/// The path almost everyone takes.
private func verifyBuyingASubscription(_ service: any PurchaseService, now: Date) async throws {
    let outcome = try await service.purchase(NextPlusProducts.primary)

    guard case .purchased(let granted) = outcome else {
        throw PurchaseContractViolation(
            requirement: "buying the recommended product completes",
            detail: "got \(outcome)"
        )
    }

    try requirePurchase(
        granted.tier(at: now) == .plus,
        "a completed purchase reports the access it granted",
        "got \(granted)"
    )

    let current = try await service.currentEntitlement()
    try requirePurchase(
        current.tier(at: now) == .plus,
        "and the service agrees a moment later",
        "got \(current)"
    )

    // Restore and the live read are two routes to one truth. A paywall that shows a different
    // answer depending on which one it happened to call is worse than either.
    let restored = try await service.restore()
    try requirePurchase(
        restored.tier(at: now) == current.tier(at: now),
        "restoring agrees with the current entitlement",
        "restore said \(restored), current said \(current)"
    )
}

/// The purchase that never expires.
private func verifyBuyingLifetime(_ service: any PurchaseService, now: Date) async throws {
    let outcome = try await service.purchase(NextPlusProducts.lifetime)

    guard case .purchased(let granted) = outcome else {
        throw PurchaseContractViolation(
            requirement: "buying the lifetime product completes",
            detail: "got \(outcome)"
        )
    }

    try requirePurchase(
        granted.isLifetime,
        "a one-off purchase is recorded as one rather than as a period",
        "got \(granted)"
    )
    try requirePurchase(
        granted.tier(at: now.addingTimeInterval(100 * 365 * 24 * 3600)) == .plus,
        "and it does not run out",
        "got \(granted)"
    )
}

/// An identifier the store does not sell.
private func verifyUnsellableProduct(_ service: any PurchaseService) async throws {
    // Reachable through a typo in a product identifier, which is otherwise invisible until a real
    // purchase silently fails to resolve. It must be an error, not a shrug that grants nothing
    // and says nothing.
    let imaginary = ProductID("com.nextapp.next.plus.not-a-real-product")

    do {
        let outcome = try await service.purchase(imaginary)
        throw PurchaseContractViolation(
            requirement: "buying a product the store does not sell fails loudly",
            detail: "got \(outcome)"
        )
    } catch let error as PurchaseError {
        try requirePurchase(
            error == .productUnavailable(imaginary),
            "and says which product was missing",
            "got \(error)"
        )
    }
}
