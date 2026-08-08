/// The result of asking the engine what to do next.
///
/// Deliberately not `Recommendation?`. The product spec requires NEXT to explain an empty
/// screen — "if no viable alternative exists, say so clearly" — so the absence of a
/// recommendation always carries a reason the UI can render honestly.
public enum RecommendationOutcome: Hashable, Sendable {

    /// There is something to do, and this is it.
    case recommended(Recommendation)

    /// The user has no tasks at all. This is the empty-state, not a failure.
    case nothingToDo

    /// Tasks exist, but none can be recommended right now, and here is why.
    case nothingAvailable(UnavailabilityReason)

    /// The recommendation, if there was one.
    public var recommendation: Recommendation? {
        guard case .recommended(let recommendation) = self else { return nil }
        return recommendation
    }
}

/// Why the engine had tasks to consider but recommended none of them.
///
/// Each case must be renderable as a short, non-judgemental sentence. The UI never says
/// "nothing found" — it says what is actually true.
public enum UnavailabilityReason: Hashable, Sendable {

    /// Every task is completed or archived.
    case noActiveTasks

    /// The user stated a time budget and nothing fits inside it. Carries the shortest
    /// outstanding task so the UI can say something useful — "the shortest thing you have
    /// is 45 minutes" — rather than showing an unexplained blank.
    case nothingFitsAvailableTime(shortestMinutes: Int)

    /// Every outstanding task is waiting on a prerequisite that is not finished.
    case everythingBlocked
}
