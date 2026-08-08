/// Whether the task can still realistically be finished by its deadline.
///
/// This is the trigger for Minimum Win (PRODUCT_SPEC.md §4.12): once the ideal outcome is out
/// of reach, NEXT stops offering it and switches to the highest-value achievable progress.
/// Surfacing it as a plain fact — rather than as a warning or a telling-off — is deliberate.
public enum DeadlineFeasibility: Hashable, Sendable {

    /// No deadline, so there is nothing to be feasible against.
    case noDeadline

    /// There is a deadline but no duration estimate, so no honest judgement is possible.
    /// Guessing here would be inventing certainty, which the product spec forbids.
    case unknownDuration

    /// Comfortably achievable in the time remaining.
    case comfortable

    /// It fits, but only just. Worth starting now.
    case tight

    /// There is not enough time left to finish it. Minimum Win applies.
    case unreachable

    /// Whether NEXT should be offering a reduced goal instead of the original one.
    public var suggestsMinimumWin: Bool {
        self == .unreachable
    }
}
