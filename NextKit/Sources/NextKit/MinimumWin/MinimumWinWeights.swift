import Foundation

/// Every constant Minimum Win uses, in one place.
///
/// Same rule as `ScoringWeights` and for the same reason (DECISIONS.md D-008, ARCHITECTURE.md
/// §10): a number buried in the planner cannot be tuned, cannot be explained, and cannot be
/// argued with. These are shares of the user's own estimate, not invented durations — the only
/// duration knowledge in the system came from the user, and this type decides how it is split.
public struct MinimumWinWeights: Hashable, Sendable {

    // MARK: Stage shares
    //
    // Fractions of the whole task's estimate. They deliberately do not add to 1: the stages
    // describe getting properly started on something, not finishing it. Whatever is left over
    // is the rest of the work, which by definition does not fit — that is why Minimum Win was
    // triggered in the first place.

    /// Getting the shape of the whole thing down. Cheapest stage, and the one that most
    /// changes what the remaining time is worth.
    public var outlineShare: Double

    /// Producing the first real piece of the deliverable.
    public var openingShare: Double

    /// Finishing one part properly. The largest stage, because "properly" is the point —
    /// a hurried section is not progress the user can hand in or build on.
    public var firstPartShare: Double

    // MARK: Shape parameters

    /// The shortest a stage may be. A three-minute "write the introduction" is not an
    /// instruction anyone can act on, so short estimates round up to something real rather
    /// than producing a ladder made of fragments.
    public var minimumStageMinutes: Int

    /// How many rungs the user is shown at once.
    ///
    /// Three. The ladder is itself a decision, and P1 says reduce the user's decisions rather
    /// than adding to them. A task decomposed into eleven substeps must not produce an
    /// eleven-item menu; it produces three, spread across what fits.
    public var maximumRungs: Int

    public init(
        outlineShare: Double,
        openingShare: Double,
        firstPartShare: Double,
        minimumStageMinutes: Int,
        maximumRungs: Int
    ) {
        self.outlineShare = outlineShare
        self.openingShare = openingShare
        self.firstPartShare = firstPartShare
        self.minimumStageMinutes = minimumStageMinutes
        self.maximumRungs = maximumRungs
    }

    /// The shipping defaults. A considered starting point, not measured truth — the same
    /// honesty `ScoringWeights.default` states about itself.
    public static let `default` = MinimumWinWeights(
        outlineShare: 0.15,
        openingShare: 0.20,
        firstPartShare: 0.30,
        minimumStageMinutes: 5,
        maximumRungs: 3
    )

    /// The share of the whole estimate a given stage is budgeted.
    func share(for stage: MinimumWinStage) -> Double {
        switch stage {
        case .outline: outlineShare
        case .opening: openingShare
        case .firstPart: firstPartShare
        }
    }
}
