import Foundation

/// What Rescue puts on the screen: one framing line and exactly one thing to do.
///
/// Note what this type cannot express. There is no array of steps, so a view cannot decide to
/// render the whole decomposition "for context" — revealing one rung at a time is a property
/// of the data, not a convention the UI is trusted to honour (PRODUCT_SPEC.md §4.11). There is
/// likewise no free text field, so no path can grow into a conversation.
public struct RescueResponse: Hashable, Sendable {

    /// Which entry point produced this.
    public let path: RescuePath

    /// The task the step belongs to.
    public let taskID: TaskID

    /// The task's title, or `nil` when the path deliberately withholds it.
    ///
    /// "It's too much" withholds it: naming the mountain is the thing that made it too much.
    /// The other paths show it, because knowing what this belongs to is not what is wrong.
    public let taskTitle: String?

    /// The line before the step.
    public let framing: RescueFraming

    /// The single physical action being offered.
    public let step: RescueStep

    /// Which rung of the decomposition this is, counting from one.
    public let stepNumber: Int

    /// Whether asking again would reveal something further.
    ///
    /// Always `false` on the paths that hide size, even when a longer ladder exists. This is
    /// the difference between "here is the next step" and "here is step 2 of 7".
    public let hasMoreSteps: Bool

    /// How many minutes the user is being asked for, when the path asks for a bounded amount.
    /// `nil` when no commitment is being requested at all.
    public let commitmentMinutes: Int?

    public init(
        path: RescuePath,
        taskID: TaskID,
        taskTitle: String?,
        framing: RescueFraming,
        step: RescueStep,
        stepNumber: Int,
        hasMoreSteps: Bool,
        commitmentMinutes: Int?
    ) {
        self.path = path
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.framing = framing
        self.step = step
        self.stepNumber = stepNumber
        self.hasMoreSteps = hasMoreSteps
        self.commitmentMinutes = commitmentMinutes
    }

    /// The response as rendered text: the framing, then the step. Always exactly two lines.
    public var lines: [String] {
        [framing.sentence, step.text]
    }
}

/// The result of asking Rescue for help.
///
/// Only the time-budget path can come back empty — the others are given a task and can always
/// shrink it. When it does come back empty it says why, for the same reason the ranking engine
/// does: an unexplained blank screen is worse than an honest sentence.
public enum RescueOutcome: Hashable, Sendable {

    /// Here is one thing to do.
    case guidance(RescueResponse)

    /// The user has no tasks at all.
    case nothingToDo

    /// There are tasks, but none can be offered in this window, and here is why.
    case nothingAvailable(UnavailabilityReason)

    /// The guidance, if there was any.
    public var response: RescueResponse? {
        guard case .guidance(let response) = self else { return nil }
        return response
    }
}
