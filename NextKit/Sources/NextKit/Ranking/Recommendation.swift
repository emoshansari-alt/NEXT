import Foundation

/// The single thing NEXT is telling the user to do.
public struct Recommendation: Hashable, Sendable {

    /// The task the action belongs to.
    public let task: TaskItem

    /// Why it won, itemised.
    public let score: ScoreBreakdown

    /// The answer to "Why this?", derived from `score` so the two can never disagree.
    public let explanation: ExplanationReason

    /// Whether the original goal is still achievable by its deadline. When `.unreachable`,
    /// the UI should offer Minimum Win rather than the whole task.
    public let deadlineFeasibility: DeadlineFeasibility

    /// True when this is a task the user recently said "Not this" to, and it is being offered
    /// anyway because nothing better was available.
    ///
    /// The UI must acknowledge this rather than silently re-serving a rejected task as though
    /// the rejection never happened — that would read as the app ignoring the user.
    public let wasRecentlyRejected: Bool

    /// The concrete thing to put on the START button: the recorded next action if there is
    /// one, otherwise the task title itself.
    public var actionText: String {
        guard let nextAction = task.nextAction?.trimmingCharacters(in: .whitespacesAndNewlines),
              !nextAction.isEmpty
        else { return task.title }
        return nextAction
    }

    public init(
        task: TaskItem,
        score: ScoreBreakdown,
        explanation: ExplanationReason,
        deadlineFeasibility: DeadlineFeasibility,
        wasRecentlyRejected: Bool
    ) {
        self.task = task
        self.score = score
        self.explanation = explanation
        self.deadlineFeasibility = deadlineFeasibility
        self.wasRecentlyRejected = wasRecentlyRejected
    }
}
