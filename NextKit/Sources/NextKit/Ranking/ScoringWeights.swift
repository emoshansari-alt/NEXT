import Foundation

/// Every constant that affects ranking, in one place.
///
/// This type is the *only* legal home for a scoring number (DECISIONS.md D-008). A magic
/// constant anywhere else in the ranking code is a defect: it makes the engine impossible to
/// tune, impossible to explain, and impossible to reason about as a whole.
///
/// Each factor is computed as a normalised `0...1` signal and then multiplied by its weight
/// here. That separation is what keeps the numbers below comparable to each other — a weight
/// is literally "how many points is this factor worth at full strength".
public struct ScoringWeights: Hashable, Sendable {

    // MARK: Positive factors

    /// How close the deadline is. Weighted highest because deadlines are what actually
    /// generate the pressure this app exists to relieve — a student with a paper due tomorrow
    /// does not want to be told to do something more "important" next week.
    public var deadlineUrgency: Double

    /// Already past its deadline. Stacks on top of full urgency, so an overdue task
    /// reliably surfaces above merely imminent ones.
    public var overdueRelevance: Double

    /// Finishing this unblocks other work. Ranked above raw importance because unblocking
    /// changes what the user is able to do next, which is the app's whole purpose.
    public var unlockValue: Double

    /// The user marked it Important. Deliberately smaller than urgency: importance is meant
    /// to break near-ties, not to let a distant task outrank an imminent one.
    public var importance: Double

    /// A concrete first step already exists, so there is nothing to decide before starting.
    public var startability: Double

    /// Fits the time and circumstances available right now.
    public var contextualFit: Double

    // MARK: Penalties — subtracted

    /// Something makes this harder to begin than its size suggests.
    public var friction: Double

    /// The user recently said "Not this". Large enough to reliably move the task below any
    /// reasonable alternative, but finite: if nothing else is available the task can return,
    /// because silently recommending nothing would be worse.
    public var rejectionPenalty: Double

    // MARK: Shape parameters

    /// How far ahead a deadline has to be before it stops contributing urgency at all.
    /// Seven days: beyond about a week students do not experience a deadline as pressing,
    /// and letting distant deadlines contribute would flatten the ranking.
    public var urgencyHorizon: TimeInterval

    /// How long a "Not this" rejection keeps suppressing a task.
    public var rejectionCooldown: TimeInterval

    /// How many dependent tasks count as "fully unlocking". Beyond this the factor saturates,
    /// so a hub task with twenty dependents does not permanently dominate the ranking.
    public var unlockSaturationCount: Int

    /// How much slack a deadline needs before it stops being `tight`. At 3, a 30-minute task
    /// is comfortable only when at least 90 minutes remain — the margin exists because
    /// estimates are optimistic and students rarely get an uninterrupted run at anything.
    public var tightDeadlineMultiplier: Double

    public init(
        deadlineUrgency: Double,
        overdueRelevance: Double,
        unlockValue: Double,
        importance: Double,
        startability: Double,
        contextualFit: Double,
        friction: Double,
        rejectionPenalty: Double,
        urgencyHorizon: TimeInterval,
        rejectionCooldown: TimeInterval,
        unlockSaturationCount: Int,
        tightDeadlineMultiplier: Double
    ) {
        self.deadlineUrgency = deadlineUrgency
        self.overdueRelevance = overdueRelevance
        self.unlockValue = unlockValue
        self.importance = importance
        self.startability = startability
        self.contextualFit = contextualFit
        self.friction = friction
        self.rejectionPenalty = rejectionPenalty
        self.urgencyHorizon = urgencyHorizon
        self.rejectionCooldown = rejectionCooldown
        self.unlockSaturationCount = unlockSaturationCount
        self.tightDeadlineMultiplier = tightDeadlineMultiplier
    }

    /// The shipping defaults.
    ///
    /// These are a considered starting point, not measured truth. The product spec identifies
    /// recommendation *rejection rate* as the signal most likely to justify changing them,
    /// so they are expected to move once there is evidence.
    public static let `default` = ScoringWeights(
        deadlineUrgency: 40,
        overdueRelevance: 25,
        unlockValue: 12,
        importance: 15,
        startability: 10,
        contextualFit: 10,
        friction: 8,
        rejectionPenalty: 60,
        urgencyHorizon: 7 * 24 * 3600,
        rejectionCooldown: 4 * 3600,
        unlockSaturationCount: 3,
        tightDeadlineMultiplier: 3
    )

    /// The weight applied to a given factor.
    func weight(for factor: RankingFactor) -> Double {
        switch factor {
        case .deadlineUrgency: deadlineUrgency
        case .overdueRelevance: overdueRelevance
        case .unlockValue: unlockValue
        case .importance: importance
        case .startability: startability
        case .contextualFit: contextualFit
        case .friction: friction
        case .rejectionPenalty: rejectionPenalty
        }
    }
}
