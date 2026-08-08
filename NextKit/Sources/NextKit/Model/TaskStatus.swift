/// The lifecycle state of a task.
///
/// Note what is *not* here: "blocked". Being blocked is not a stored state the user manages —
/// it is derived at ranking time from whether a task's prerequisites are still outstanding.
/// Storing it would let the two drift apart.
public enum TaskStatus: String, Hashable, Sendable, Codable, CaseIterable {
    /// Outstanding, and a candidate for recommendation.
    case active

    /// Finished by the user.
    case completed

    /// Deliberately set aside. Retained for the user's records, never recommended.
    case archived

    /// Whether a task in this state can ever be recommended.
    var isRecommendable: Bool {
        self == .active
    }
}
