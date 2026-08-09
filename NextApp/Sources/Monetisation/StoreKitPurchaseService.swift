import Foundation
import NextKit
import StoreKit

/// The one place in NEXT that imports StoreKit.
///
/// Everything above it — what a purchase entitles someone to, when a subscription has run out,
/// whether a capability is available — is decided in `NextKit` against plain values
/// (ARCHITECTURE.md §5, DECISIONS.md D-002). This type does the two things that genuinely need
/// Apple: fetching products, and turning transactions into `EntitlementRecord`s. That mapping is
/// field-for-field and contains no rules, which is deliberate: rules that live here could only
/// ever be tested on a Simulator.
struct StoreKitPurchaseService: PurchaseService {

    /// Products, in the order NEXT presents them.
    func products() async throws -> [PurchasableProduct] {
        let fetched = try await storeProducts()

        // Ordered by the catalogue rather than by whatever the store returned. A paywall whose
        // options move between launches is disorienting, and the recommended option leads.
        return NextPlusProducts.all.compactMap { id in
            guard let product = fetched.first(where: { $0.id == id.rawValue }),
                  let kind = NextPlusProducts.kind(of: id)
            else { return nil }

            return PurchasableProduct(
                id: id,
                kind: kind,
                displayName: product.displayName,
                // The store's own string, never a number NEXT formats. Currency placement,
                // separators and tax display are Apple's to know and not the client's to guess.
                displayPrice: product.displayPrice
            )
        }
    }

    func purchase(_ id: ProductID) async throws -> PurchaseOutcome {
        guard AppStore.canMakePayments else { throw PurchaseError.notAllowed }

        let fetched = try await storeProducts()
        guard let product = fetched.first(where: { $0.id == id.rawValue }) else {
            throw PurchaseError.productUnavailable(id)
        }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch StoreKitError.networkError {
            throw PurchaseError.networkUnavailable
        } catch StoreKitError.notAvailableInStorefront {
            throw PurchaseError.productUnavailable(id)
        } catch {
            throw PurchaseError.storeUnavailable
        }

        switch result {
        case .success(let verification):
            // An unverified transaction is refused rather than trusted. A signature that does not
            // check out is the one case where granting nothing is the safe answer.
            guard case .verified(let transaction) = verification else {
                throw PurchaseError.verificationFailed
            }
            // Unfinished transactions are re-delivered forever, so this is not optional.
            await transaction.finish()
            return .purchased(try await currentEntitlement())

        case .userCancelled:
            return .cancelled

        case .pending:
            return .pendingApproval

        @unknown default:
            // A result this build does not understand. Rather than guess, ask what the person is
            // actually entitled to now: if the purchase went through, say so; otherwise treat it
            // as still in flight, which is the claim that cannot be wrong in either direction.
            let entitlement = try await currentEntitlement()
            return entitlement.isLifetime || entitlement.subscriptionExpiry != nil
                ? .purchased(entitlement)
                : .pendingApproval
        }
    }

    /// Re-reads what this Apple ID owns.
    ///
    /// Deliberately **not** `AppStore.sync()`. In StoreKit 2 entitlements follow the Apple ID and
    /// are already present after a reinstall, so re-reading them is what actually restores a
    /// purchase; `sync()` exists for the rarer case where the person needs to re-authenticate,
    /// and calling it here would put a password prompt in front of everyone who taps Restore.
    ///
    /// That a true reinstall restores correctly is a device claim, not a Simulator one — it sits
    /// in `RELEASE_GATED.md` B4 with the rest of the sandbox work.
    func restore() async throws -> EntitlementState {
        try await currentEntitlement()
    }

    func currentEntitlement() async throws -> EntitlementState {
        EntitlementResolver.resolve(await entitlementRecords())
    }

    // MARK: - StoreKit, converted to plain values

    private func storeProducts() async throws -> [Product] {
        do {
            return try await Product.products(for: NextPlusProducts.all.map(\.rawValue))
        } catch StoreKitError.networkError {
            throw PurchaseError.networkUnavailable
        } catch {
            throw PurchaseError.storeUnavailable
        }
    }

    private func entitlementRecords() async -> [EntitlementRecord] {
        let retrying = await productsInBillingRetry()
        var records: [EntitlementRecord] = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            records.append(
                EntitlementRecord(
                    productID: ProductID(transaction.productID),
                    purchaseDate: transaction.purchaseDate,
                    expirationDate: transaction.expirationDate,
                    isInBillingRetry: retrying.contains(transaction.productID),
                    // Usually nil, because a revoked transaction is already excluded from
                    // `currentEntitlements`. Carried anyway so the rule lives in one place
                    // rather than depending on StoreKit continuing to filter.
                    revocationDate: transaction.revocationDate
                )
            )
        }

        return records
    }

    /// Which subscriptions Apple is currently retrying payment for.
    ///
    /// Renewal state is not on the transaction, so it has to be asked for separately. A failure
    /// here means no grace is extended rather than an error surfaced: the person is either
    /// entitled by an unexpired period or they are not, and neither answer should depend on a
    /// secondary query succeeding.
    private func productsInBillingRetry() async -> Set<String> {
        guard let fetched = try? await storeProducts(),
              let group = fetched.compactMap({ $0.subscription?.subscriptionGroupID }).first,
              let statuses = try? await Product.SubscriptionInfo.status(for: group)
        else { return [] }

        var retrying: Set<String> = []
        for status in statuses where status.state == .inBillingRetryPeriod {
            guard case .verified(let transaction) = status.transaction else { continue }
            retrying.insert(transaction.productID)
        }
        return retrying
    }
}

/// Finishes transactions that arrive from outside a purchase.
///
/// Renewals, Ask to Buy approvals that land days later, and purchases made on another device all
/// arrive through `Transaction.updates` rather than as the result of a `purchase()` call. An
/// unfinished transaction is re-delivered indefinitely, so something has to be listening for the
/// whole life of the app — which is why this is separate from the service: the service answers
/// questions, and this exists only to keep the queue clean.
@MainActor
final class StoreKitTransactionListener {

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }

        task = Task.detached {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
            }
        }
    }

    deinit {
        task?.cancel()
    }
}
