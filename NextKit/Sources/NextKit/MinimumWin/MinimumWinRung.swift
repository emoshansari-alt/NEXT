import Foundation

/// One achievable outcome, and the work that reaches it.
///
/// A rung is *cumulative*: reaching its `goal` means having done everything in
/// `leadingSteps` first. That is why the ladder can be ordered by ambition at all — the rungs
/// are points along one sequence, not a menu of unrelated fragments.
///
/// `goal` is stored separately from the steps before it so that a rung is non-empty by
/// construction. A rung with nothing in it would be a blank screen with a duration attached.
public struct MinimumWinRung: Hashable, Sendable {

    /// The furthest point this rung reaches — the headline the user reads.
    public let goal: MinimumWinStep

    /// The work that has to happen before `goal`, in order. Empty on the smallest rung.
    public let leadingSteps: [MinimumWinStep]

    /// How long this rung asks for. Never more than the time actually remaining.
    ///
    /// For an ordinary rung this is the sum of its steps. For a time-boxed one it is the
    /// whole remaining window, which is less than the goal needs — see `isTimeBoxed`.
    public let minutes: Int

    /// Whether the goal is reached in full.
    ///
    /// `true` means it is not: there was not enough time for even the smallest whole piece of
    /// work, so what is offered is the window itself spent on the first thing. Saying "nothing
    /// fits" would be true and useless; pretending the goal completes would be a lie. This is
    /// the honest third answer.
    public let isTimeBoxed: Bool

    /// Everything this rung asks for, in the order it happens. Never empty.
    public var steps: [MinimumWinStep] {
        leadingSteps + [goal]
    }

    public init(
        goal: MinimumWinStep,
        leadingSteps: [MinimumWinStep] = [],
        minutes: Int,
        isTimeBoxed: Bool = false
    ) {
        self.goal = goal
        self.leadingSteps = leadingSteps
        self.minutes = minutes
        self.isTimeBoxed = isTimeBoxed
    }
}
