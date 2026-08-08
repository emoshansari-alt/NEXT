import Foundation

/// One piece of work inside a Minimum Win rung.
///
/// Unlike a `RescueStep`, a step here always carries a length. That is not decoration: the
/// entire promise of Minimum Win is that what it offers fits in the time left, and a step of
/// unknown length cannot be part of a promise like that. Where the user gave no estimate the
/// planner allocates one from the estimate they did give, and says so via
/// `hasRecordedDuration` rather than passing the allocation off as knowledge.
public struct MinimumWinStep: Hashable, Sendable {

    /// The instruction, punctuated and ready to render.
    public let text: String

    /// How long this step is budgeted. Always at least one minute.
    public let minutes: Int

    /// Where the step came from.
    public let origin: MinimumWinStepOrigin

    /// Whether `minutes` is a duration the user actually recorded, or one the planner
    /// allocated out of the whole task's estimate.
    public let hasRecordedDuration: Bool

    public init(
        text: String,
        minutes: Int,
        origin: MinimumWinStepOrigin,
        hasRecordedDuration: Bool
    ) {
        self.text = text
        self.minutes = minutes
        self.origin = origin
        self.hasRecordedDuration = hasRecordedDuration
    }
}

/// Where a `MinimumWinStep` came from.
public enum MinimumWinStepOrigin: Hashable, Sendable {

    /// A real substep — a child task the user or a decomposition recorded. The strongest
    /// signal available, because nothing about it was inferred.
    case substep(TaskID)

    /// A generic stage of work, chosen because the task said nothing about its own shape.
    case stage(MinimumWinStage)

    /// Whether this reflects work the user actually recorded rather than a generic stage.
    public var isRecordedByUser: Bool {
        switch self {
        case .substep: true
        case .stage: false
        }
    }
}
