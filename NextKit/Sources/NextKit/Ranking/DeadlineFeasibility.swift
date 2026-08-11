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

    /// There is not enough time left to finish it, and the deadline is **still ahead**.
    /// Minimum Win applies: there is a window, and something smaller can be fitted into it.
    case unreachable

    /// The deadline has been reached or has gone by. There is no window left at all.
    ///
    /// Separated from `unreachable` because the two are different facts and the app says
    /// different things about them — "there is not enough time left to finish this" describes a
    /// window that is too small, and claiming it once the deadline has passed describes a window
    /// that does not exist (D-030).
    ///
    /// **A deadline exactly reached counts as passed.** A zero-length window cannot contain work,
    /// so treating the instant of the deadline as "still ahead" would be a distinction with no
    /// consequence — and drawing the line at `<= 0` keeps it away from the sub-minute region
    /// where integer truncation used to decide the answer.
    case passed

    /// Whether NEXT should be offering something smaller than the original goal.
    ///
    /// True for both out-of-time states. Where the *reduced goal* comes from differs, and that
    /// is the architectural boundary D-030 settles: while the deadline is ahead, Minimum Win
    /// plans against the window that remains; once it has passed there is no such window, and
    /// Rescue plans against an amount of time the user says they have now. One question, two
    /// owners, decided by which of these cases applies.
    public var suggestsMinimumWin: Bool {
        self == .unreachable || self == .passed
    }

    /// Whether the deadline itself has gone, as opposed to merely being unmeetable.
    public var deadlineHasPassed: Bool {
        self == .passed
    }
}
