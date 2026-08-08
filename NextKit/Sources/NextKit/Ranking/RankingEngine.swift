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

    public init() {}

    /// Returns the single best thing to do now, or an explained reason there is nothing.
    public func recommend(
        from tasks: [TaskItem],
        context: RankingContext
    ) -> RecommendationOutcome {
        guard !tasks.isEmpty else { return .nothingToDo }

        let eligible = tasks.filter { $0.status.isRecommendable }

        guard let best = eligible.first else {
            return .nothingAvailable(.noActiveTasks)
        }

        return .recommended(Recommendation(task: best))
    }
}
