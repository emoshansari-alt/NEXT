import Foundation

/// A capability NEXT has, named so that whether it costs money is a table entry rather than an
/// `if` statement scattered through the views.
///
/// **These are the capabilities NEXT actually has today** — not a wishlist. The NEXT+ categories
/// recorded in `DECISIONS.md` **D-034** are deliberately absent: naming a feature here is how it
/// starts being treated as a commitment, and none of them has been built.
///
/// Every case below is **core, and free permanently** (D-034). NEXT+ is enhancement, never access
/// to what the product already does, so nothing in this enum will ever gain a paid row. A future
/// premium capability arrives as a *new* case alongside these.
public enum PremiumCapability: String, Hashable, Sendable, Codable, CaseIterable {

    /// Turning a brain dump into separate tasks.
    case brainDumpExtraction

    /// Breaking one task into steps.
    case taskDecomposition

    /// The four "I'm stuck" paths.
    case rescue

    /// The smallest honest next rung.
    case minimumWin

    /// The home-screen widget.
    case homeScreenWidget

    /// Deadline and daily reminders.
    case reminders
}

/// Whether a capability may be used right now.
public enum CapabilityAccess: Hashable, Sendable {

    /// Go ahead.
    case allowed

    /// This one is paid for, and the person is not paying. Show the paywall — but only because
    /// they asked for the capability, never at launch (`PRODUCT_SPEC.md` §12).
    case offerUpgrade

    /// The store has not answered yet.
    ///
    /// Not "no". A screen seeing this should wait, not sell. The difference is what stops a
    /// subscriber being shown a paywall for something they already own because the network was
    /// slow at launch.
    case undetermined
}

/// Which capabilities cost money.
///
/// The table is a value the gate is constructed with, not a global it reaches for. That is what
/// lets these rules be proven against gated capabilities while the shipped table gates nothing.
public struct FeatureGate: Hashable, Sendable {

    private let requirements: [PremiumCapability: NextTier]

    public init(requirements: [PremiumCapability: NextTier]) {
        self.requirements = requirements
    }

    /// The tier a capability needs.
    ///
    /// A capability with no row is **free**. That is the safe direction: forgetting to add a row
    /// must not put something behind a paywall by accident, whereas charging for something has
    /// to be a deliberate edit.
    public func requiredTier(for capability: PremiumCapability) -> NextTier {
        requirements[capability] ?? .free
    }

    /// Whether the table says anything about this capability at all.
    ///
    /// Used by the tripwire test: a table that lists every capability as free is a statement,
    /// while an empty one merely behaves that way today.
    public func hasExplicitRow(for capability: PremiumCapability) -> Bool {
        requirements[capability] != nil
    }

    /// What a person of this status may do with this capability.
    public func access(
        to capability: PremiumCapability,
        given status: EntitlementStatus
    ) -> CapabilityAccess {
        // Checked before the status, and that order is the rule: a free capability must not wait
        // on StoreKit. Every capability in 1.0 is free, so the opposite order would leave the
        // entire app inert whenever the store was slow to answer.
        guard requiredTier(for: capability) == .plus else { return .allowed }

        switch status {
        case .plus: return .allowed
        case .free: return .offerUpgrade
        case .unknown: return .undetermined
        }
    }

    /// What NEXT 1.0 ships: nothing behind the paywall.
    ///
    /// This is now a **conclusion rather than a placeholder**. D-034 settled the boundary — NEXT+
    /// is enhancement, never core access — and applying it to what exists today gates nothing,
    /// because every capability NEXT has is core. All of them stay free permanently, and not as
    /// an interim position: taking a working feature away to manufacture a paid tier is not
    /// something this product does.
    ///
    /// So this table does not change when NEXT+ becomes real. A premium capability arrives as a
    /// new `PremiumCapability` case with its own `.plus` row, and D-019 has to be answered before
    /// the first one does.
    ///
    /// Every capability is listed rather than left to the default, so this reads as the decision
    /// it is. `FeatureGateTests.oneDotZeroGatesNothing` is the tripwire.
    public static let oneDotZero = FeatureGate(
        requirements: Dictionary(
            uniqueKeysWithValues: PremiumCapability.allCases.map { ($0, NextTier.free) }
        )
    )
}
