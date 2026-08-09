import Foundation
import NextKit
import Observation

/// Whether the paywall can be reached at all.
///
/// **It cannot, in a normal build.** The entitlement machinery, the products and the paywall are
/// complete and verified, and NEXT+ unlocks nothing (`FeatureGate.oneDotZero`), so offering it
/// for sale would be selling something that does not exist. Rather than leave the screen
/// half-written until the NEXT+ boundary is decided, it is finished and put behind a launch
/// argument the test targets use — the same device `PRODUCT_SPEC.md` §4 already sanctions for
/// debug surfaces excluded from production builds.
///
/// Making it reachable is one line here plus the boundary decision in `DECISIONS.md` that has to
/// exist first. `RELEASE_CHECKLIST.md` carries a blocking item so the choice is made deliberately
/// rather than discovered at submission.
enum MonetisationAvailability {

    static let testingArgument = "-storekit-testing"

    static var isPaywallReachable: Bool {
        ProcessInfo.processInfo.arguments.contains(testingArgument)
    }
}

/// The paywall's state.
@MainActor
@Observable
final class PaywallViewModel {

    private(set) var products: [PurchasableProduct] = []

    /// What NEXT knows about the person's tier.
    ///
    /// Starts `.unknown` and **never becomes `.free` because something went wrong**. A store that
    /// could not be reached tells you nothing about what someone has paid for, and the difference
    /// between "not entitled" and "not known" is the difference between a subscriber seeing their
    /// subscription and a subscriber being asked to buy it again.
    private(set) var status: EntitlementStatus = .unknown

    /// Something worth saying out loud — a failure, or the result of a purchase or restore.
    private(set) var notice: String?

    private(set) var isWorking = false

    private let service: any PurchaseService
    private let timeSource: any TimeSource

    init(
        service: any PurchaseService = StoreKitPurchaseService(),
        timeSource: any TimeSource = SystemTimeSource()
    ) {
        self.service = service
        self.timeSource = timeSource
    }

    /// What the screen may claim NEXT+ unlocks. Empty while nothing is gated.
    var benefits: [String] { NextPlusCopy.benefits }

    var isPlus: Bool { status == .plus }

    func load() async {
        isWorking = true
        defer { isWorking = false }

        do {
            products = try await service.products()
        } catch {
            notice = message(for: error)
        }

        await refreshEntitlement()
    }

    func buy(_ id: ProductID) async {
        isWorking = true
        defer { isWorking = false }
        notice = nil

        do {
            switch try await service.purchase(id) {
            case .purchased(let state):
                status = state.status(at: timeSource.now)
                notice = NextPlusCopy.purchased

            case .pendingApproval:
                notice = NextPlusCopy.pending

            case .cancelled:
                // Closing the sheet is not an event worth reporting back to the person who did it.
                break
            }
        } catch {
            notice = message(for: error)
        }
    }

    func restore() async {
        isWorking = true
        defer { isWorking = false }
        notice = nil

        do {
            let state = try await service.restore()
            status = state.status(at: timeSource.now)
            notice = status == .plus ? NextPlusCopy.restoredSomething : NextPlusCopy.restoredNothing
        } catch {
            notice = message(for: error)
        }
    }

    private func refreshEntitlement() async {
        do {
            status = try await service.currentEntitlement().status(at: timeSource.now)
        } catch {
            // Left `.unknown` on purpose. See `status`.
            notice = notice ?? message(for: error)
        }
    }

    private func message(for error: any Error) -> String {
        (error as? PurchaseError)?.errorDescription
            ?? PurchaseError.storeUnavailable.errorDescription
            ?? ""
    }
}
