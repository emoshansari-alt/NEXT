/// The five things NEXT ever asks a model to do.
///
/// A closed set, for the same reason `RescuePath` is closed: an open-ended "ask the model
/// anything" surface is a chatbot, and PRODUCT_SPEC.md §1 says NEXT is not one. Every operation
/// here maps to a specific product moment, has a typed request carrying the minimum context for
/// that moment alone, and has a deterministic answer available when no model is reachable.
///
/// What is deliberately *absent* is the other half of PRODUCT_SPEC.md §6: there is no operation
/// for deleting, completing, ranking, purchasing, navigating or scheduling. A model cannot ask
/// for those things because there is no way to express the request.
public enum IntelligenceOperation: String, Hashable, Sendable, CaseIterable, Codable {

    /// Turn a brain dump into separate tasks. The Capture screen.
    case extractTasks

    /// Break one task into steps. "Break it down" on Task Detail.
    case decompose

    /// Produce the single concrete first step for one task.
    case nextAction

    /// Guess how long one task will take.
    case estimateDuration

    /// Produce a smaller step for someone who is stuck. Rescue.
    case simplify
}
