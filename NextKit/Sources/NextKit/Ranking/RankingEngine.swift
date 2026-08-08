import Foundation

/// Decides what the user should do next.
///
/// This is the heart of NEXT and it is deliberately a **pure function**: given the same tasks,
/// the same context and the same `now`, it always returns the same answer. No clock reads, no
/// randomness, no I/O, no model call. A cloud LLM is never the decision-maker here
/// (PRODUCT_SPEC.md §5).
///
/// Ranking happens in two distinct stages, kept separate so that an empty result is always
/// explainable:
///
/// 1. **Filter** — discard tasks that are ineligible right now.
/// 2. **Score** — rank whatever survives.
///
/// If the filter empties the list, the engine reports *why* rather than recommending something
/// ineligible or returning a bare nothing.
public struct RankingEngine: Sendable {

    public let weights: ScoringWeights

    public init(weights: ScoringWeights = .default) {
        self.weights = weights
    }

    // MARK: - Recommending

    /// Returns the single best thing to do now, or an explained reason there is nothing.
    public func recommend(
        from tasks: [TaskItem],
        context: RankingContext
    ) -> RecommendationOutcome {
        guard !tasks.isEmpty else { return .nothingToDo }

        let eligible = tasks.filter { $0.status.isRecommendable }

        guard !eligible.isEmpty else {
            return .nothingAvailable(.noActiveTasks)
        }

        let ranked = eligible
            .map { (task: $0, score: score($0, context: context)) }
            .sorted { outranks($0, $1) }

        guard let best = ranked.first else {
            return .nothingAvailable(.noActiveTasks)
        }

        return .recommended(Recommendation(task: best.task))
    }

    // MARK: - Scoring

    /// The full, itemised score for one task. Public because "Why this?" is built from it and
    /// because it is the unit the tests pin behaviour to.
    public func score(_ task: TaskItem, context: RankingContext) -> ScoreBreakdown {
        var factors: [RankingFactor: Double] = [:]

        // Every factor is written, including the ones that do not apply, so that a breakdown
        // is always complete. Absent must be spelled zero.
        for factor in RankingFactor.allCases {
            let signal = self.signal(for: factor, task: task, context: context)
            let contribution = signal * weights.weight(for: factor)
            factors[factor] = factor.isPenalty ? -contribution : contribution
        }

        return ScoreBreakdown(factors: factors)
    }

    /// The normalised `0...1` strength of one factor for one task.
    ///
    /// Keeping every factor on the same scale is what makes the weights in `ScoringWeights`
    /// meaningfully comparable to one another.
    private func signal(
        for factor: RankingFactor,
        task: TaskItem,
        context: RankingContext
    ) -> Double {
        switch factor {
        case .deadlineUrgency:
            urgencySignal(deadline: task.deadline, now: context.now)

        case .overdueRelevance:
            task.isOverdue(at: context.now) ? 1 : 0

        case .importance:
            task.importance.signal

        // Not yet implemented. Each is driven in by its own test in a later cycle; until then
        // it contributes an explicit zero rather than being silently missing.
        case .unlockValue, .startability, .contextualFit, .friction, .rejectionPenalty:
            0
        }
    }

    /// How pressing a deadline is, from 0 (beyond the horizon, or undated) to 1 (due now or
    /// already past).
    private func urgencySignal(deadline: Date?, now: Date) -> Double {
        guard let deadline else { return 0 }

        let remaining = deadline.timeIntervalSince(now)
        guard remaining > 0 else { return 1 }

        let horizon = weights.urgencyHorizon
        guard horizon > 0 else { return 1 }

        return max(0, min(1, 1 - remaining / horizon))
    }

    // MARK: - Ordering

    private typealias Scored = (task: TaskItem, score: ScoreBreakdown)

    /// A total ordering over scored tasks.
    ///
    /// It must be *total*, not merely a comparison: two tasks that score identically still
    /// have to resolve the same way on every call, regardless of the order they arrived in.
    /// Falling back to the identifier guarantees that, since identifiers are unique.
    private func outranks(_ lhs: Scored, _ rhs: Scored) -> Bool {
        let delta = lhs.score.total - rhs.score.total
        if abs(delta) > 1e-9 { return delta > 0 }

        // Equal scores: the nearer deadline first, undated last.
        switch (lhs.task.deadline, rhs.task.deadline) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            break
        }

        // Then the one the user has been carrying longest.
        if lhs.task.createdAt != rhs.task.createdAt {
            return lhs.task.createdAt < rhs.task.createdAt
        }

        return lhs.task.id.rawValue < rhs.task.id.rawValue
    }
}
