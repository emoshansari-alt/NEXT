import Foundation

/// The ladder NEXT offers when the ideal outcome is out of reach.
///
/// Most ambitious rung first, every rung provably inside the time that is left
/// (PRODUCT_SPEC.md §4.12). Non-empty by construction: `best` is a stored rung, not the first
/// element of a list that might be empty, so no caller can be handed a plan with nothing in it.
public struct MinimumWinPlan: Hashable, Sendable {

    /// The task whose goal is being reduced.
    public let taskID: TaskID

    /// Its title. Shown, unlike in Rescue's "it's too much" path — the user has not asked for
    /// the size of the thing to be hidden here, they have asked what is still possible.
    public let taskTitle: String

    /// Whole minutes between the moment planned for and the deadline. Always at least one.
    public let minutesRemaining: Int

    /// Where the rungs came from, so the app layer can be honest about generic advice.
    public let source: MinimumWinSource

    /// The one line that goes above the ladder.
    public let framing: MinimumWinFraming

    /// The most ambitious outcome that fits.
    public let best: MinimumWinRung

    /// Less ambitious alternatives, each smaller than the one before.
    public let smallerRungs: [MinimumWinRung]

    /// When to stop and look at this again.
    ///
    /// The end of the *top* rung, not the deadline. "Reassess" is the last item in the spec's
    /// worked example, and it means looking again once real progress exists — the situation at
    /// that point is genuinely different from the one being planned for now.
    public let reassessAt: Date

    /// The whole ladder, most ambitious first. Never empty.
    public var rungs: [MinimumWinRung] {
        [best] + smallerRungs
    }

    public init(
        taskID: TaskID,
        taskTitle: String,
        minutesRemaining: Int,
        source: MinimumWinSource,
        framing: MinimumWinFraming,
        best: MinimumWinRung,
        smallerRungs: [MinimumWinRung],
        reassessAt: Date
    ) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.minutesRemaining = minutesRemaining
        self.source = source
        self.framing = framing
        self.best = best
        self.smallerRungs = smallerRungs
        self.reassessAt = reassessAt
    }
}

/// What the ladder was built out of.
public enum MinimumWinSource: Hashable, Sendable {

    /// The task's own outstanding substeps. Real decomposition — nothing was inferred.
    case recordedSubsteps

    /// Generic stages of work, because the task did not say how it breaks down. `kind` is
    /// what the title looked like, or `nil` when it looked like nothing in particular.
    ///
    /// Carried so the app can say the advice is generic. A generic suggestion presented as
    /// though it were tailored is the kind of small dishonesty that costs a tool its
    /// credibility the first time a user notices.
    case genericStages(WorkKind?)

    /// Whether the ladder is generic advice rather than the user's own decomposition.
    public var isGeneric: Bool {
        switch self {
        case .recordedSubsteps: false
        case .genericStages: true
        }
    }
}

/// The one line above the ladder.
///
/// Structured rather than a bare string, for the same reasons as `ExplanationReason` and
/// `RescueFraming`: the app can reword or localise without touching this module, and tests can
/// assert behaviour without pinning copy.
///
/// Both sentences state a fact about time and then point at the list. Neither mentions how the
/// situation arose. "You left this too late" is the natural sentence here and it is exactly
/// what invariant P5 forbids — the user already knows, and being told does not produce a page
/// of the paper.
public enum MinimumWinFraming: Hashable, Sendable {

    /// Whole outcomes fit in what is left.
    case hereIsWhatFits(minutesRemaining: Int)

    /// Nothing completes in what is left, so what is offered is where to spend it.
    case onlyAStartFits(minutesRemaining: Int)

    /// A short, deterministic English rendering.
    public var sentence: String {
        switch self {
        case .hereIsWhatFits(let minutes):
            "You have \(Self.duration(minutes)) left. Here is what fits."

        case .onlyAStartFits(let minutes):
            "You have \(Self.duration(minutes)) left. This is where to spend it."
        }
    }

    /// Reuses the ranking layer's duration wording, so Minimum Win, Rescue and "Why this?"
    /// never disagree about how to say two hours (ARCHITECTURE.md §10 — no duplicated logic).
    private static func duration(_ minutes: Int) -> String {
        ExplanationReason.humanised(Double(minutes) * 60)
    }
}

/// The answer to "is the ideal outcome still on?".
///
/// Deliberately not `MinimumWinPlan?`. An absent plan means one of three quite different
/// things, and collapsing them would leave the app unable to say which.
public enum MinimumWinOutcome: Hashable, Sendable {

    /// The ideal outcome is gone. Here is what is still achievable.
    case ladder(MinimumWinPlan)

    /// Nothing needs reducing, and here is the feasibility that says so. Also covers the case
    /// where no honest judgement is possible — `.unknownDuration` — because inventing
    /// certainty about a task with no estimate is a defect, not a helpful guess.
    case notNeeded(DeadlineFeasibility)

    /// The deadline is here or gone. There is no window left to fit anything into, and
    /// offering a rung would be offering something the user cannot do in time.
    case noTimeRemaining

    /// The ladder, if there was one.
    public var plan: MinimumWinPlan? {
        guard case .ladder(let plan) = self else { return nil }
        return plan
    }
}
