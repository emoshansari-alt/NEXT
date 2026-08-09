import Foundation
import Testing

@testable import NextKit

/// The table that decides what costs money, and the rules for reading it.
///
/// The gate takes its table as an argument rather than reaching for a global, so the logic can
/// be proven against gated capabilities without any capability actually being gated in the
/// shipped app. `FeatureGate.oneDotZero` — the table NEXT really ships — gates nothing, and the
/// last test in this file is the tripwire that keeps it that way.
@Suite("FeatureGate — reading the table")
struct FeatureGateTests {

    /// A hypothetical table used to prove the rules. Not the shipped one.
    private let gated = FeatureGate(requirements: [.minimumWin: .plus])

    @Test("a capability nobody pays for is available to everyone")
    func freeCapabilityIsAlwaysAllowed() {
        for status in [EntitlementStatus.unknown, .free, .plus] {
            #expect(gated.access(to: .rescue, given: status) == .allowed)
        }
    }

    @Test("a free capability is available before the store has answered")
    func freeCapabilityDoesNotWaitOnStoreKit() {
        // The important half of the rule above, stated on its own because it is the one that
        // would be broken by an innocent-looking refactor. Every capability in 1.0 is free, so
        // if an unresolved entitlement could block a free capability, launching offline or with
        // a slow App Store connection would leave the whole app inert.
        #expect(gated.access(to: .rescue, given: .unknown) == .allowed)
    }

    @Test("a paying user gets a gated capability")
    func plusGetsGatedCapability() {
        #expect(gated.access(to: .minimumWin, given: .plus) == .allowed)
    }

    @Test("a free user is offered the upgrade rather than refused")
    func freeUserIsOfferedTheUpgrade() {
        #expect(gated.access(to: .minimumWin, given: .free) == .offerUpgrade)
    }

    @Test("a gated capability waits rather than showing a paywall to an unknown user")
    func unknownEntitlementNeverShowsAPaywall() {
        // The bug this exists to prevent: a subscriber opens the app, StoreKit has not answered
        // yet, and NEXT tries to sell them something they already own. Undetermined is a third
        // answer on purpose — it is not "no".
        #expect(gated.access(to: .minimumWin, given: .unknown) == .undetermined)
    }

    @Test("a capability missing from the table is free")
    func absentMeansFree() {
        // The safe direction. Forgetting to add a row must not paywall something by accident;
        // charging for a capability has to be a deliberate edit.
        let empty = FeatureGate(requirements: [:])

        #expect(empty.requiredTier(for: .minimumWin) == .free)
        #expect(empty.access(to: .minimumWin, given: .free) == .allowed)
    }

    // MARK: The tripwire

    @Test("NEXT 1.0 puts nothing behind the paywall")
    func oneDotZeroGatesNothing() {
        // DELIBERATE, and this test is the reason it stays deliberate.
        //
        // The entitlement machinery ships complete while every capability NEXT has today stays
        // free (DECISIONS.md D-015). Moving one behind the paywall means coming here and editing
        // a test that says why it was free — which is the point. Nothing that already works for
        // a user should quietly stop working because a pricing page was written.
        for capability in PremiumCapability.allCases {
            #expect(
                FeatureGate.oneDotZero.requiredTier(for: capability) == .free,
                "\(capability) is gated; if that is intended, the NEXT+ boundary decision in DECISIONS.md must say so first"
            )
        }
    }

    @Test("the shipped table names every capability rather than relying on the default")
    func oneDotZeroIsExplicit() {
        // An empty table would also gate nothing, and would say nothing. Listing every capability
        // as free is a statement; an absent row is an oversight that happens to behave.
        for capability in PremiumCapability.allCases {
            #expect(
                FeatureGate.oneDotZero.hasExplicitRow(for: capability),
                "\(capability) has no row in the 1.0 table"
            )
        }
    }
}
