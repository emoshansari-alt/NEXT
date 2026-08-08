import Foundation

/// One physical thing the user can do right now.
///
/// A step is always a complete instruction, never a category. "Open the assignment
/// instructions." is a step; "research" is not.
public struct RescueStep: Hashable, Sendable {

    /// The instruction, punctuated and ready to render.
    public let text: String

    /// Where the step came from. Kept because it is the honest measure of how much the step
    /// can be trusted: a step the user wrote themselves is worth more than one inferred from
    /// six letters of the title, and the app layer may want to say so.
    public let origin: RescueStepOrigin

    /// How long the step is expected to take, when that is actually known. `nil` is the
    /// common case and means unknown — never "instant".
    public let estimatedMinutes: Int?

    public init(text: String, origin: RescueStepOrigin, estimatedMinutes: Int? = nil) {
        self.text = text
        self.origin = origin
        self.estimatedMinutes = estimatedMinutes
    }
}

/// Where a `RescueStep` came from.
public enum RescueStepOrigin: Hashable, Sendable {

    /// The next action already recorded on the task. The strongest signal there is: the user
    /// wrote it, so no inference is involved.
    case recordedNextAction

    /// A real substep — a child task the user or a decomposition created.
    case substep(TaskID)

    /// Inferred from the title by keyword match. A reasonable guess, and labelled as one.
    case template(WorkKind)

    /// Nothing in the task said anything useful, so this is the honest universal step.
    case generic

    /// Whether the step reflects something the user actually recorded, rather than something
    /// NEXT inferred.
    public var isFromRecordedWork: Bool {
        switch self {
        case .recordedNextAction, .substep: true
        case .template, .generic: false
        }
    }
}
