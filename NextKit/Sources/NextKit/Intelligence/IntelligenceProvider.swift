import Foundation

/// Anything that can answer NEXT's five intelligence questions.
///
/// The seam from ARCHITECTURE.md §3 and DECISIONS.md D-005. On-device, cloud, mock and template
/// implementations all sit behind it, and the Phase 8 decision about which of them ships is
/// deliberately still open — which is why **no vendor, model family, protocol or transport is
/// named anywhere in this module**. If reading this file told you who the provider was, the
/// abstraction would already have failed.
///
/// ## Every method returns `Validated`
///
/// That is the important line in the file. `Validated` has no accessible initialiser outside
/// `ResponseValidator.swift`, so a conforming type — including one written later, in another
/// module, by someone who has not read this comment — physically cannot return a value without
/// passing its response through the validator first. PRODUCT_SPEC.md §6 says no AI response can
/// corrupt the local task database; this is how that is arranged rather than merely intended.
///
/// ## Async and throwing
///
/// `async` because the only interesting implementations are I/O or on-device inference.
/// `throws` because every one of them fails routinely — no network, no consent, a timeout, a
/// response that fails the gate — and PRODUCT_SPEC.md §6 requires all of it to fail safe into
/// the deterministic layer.
///
/// Untyped `throws` is deliberate even though `IntelligenceError` is the intended currency:
/// a provider in `NextApp` may surface a `CancellationError` from the concurrency runtime, and
/// forcing every such error through a translation layer buys nothing.
///
/// ## What a provider is never asked
///
/// There is no method here for deleting, completing, ranking, purchasing, navigating or
/// scheduling a notification. PRODUCT_SPEC.md §6 lists those as things AI must never own, and
/// the enforcement is that there is no way to ask.
public protocol IntelligenceProvider: Sendable {

    /// The operations this provider can actually do.
    ///
    /// Not every provider does everything, and saying so plainly is better than answering badly.
    /// `TemplateFallbackProvider` omits `estimateDuration` because there is no honest
    /// deterministic answer to "how long will this take" — see that type.
    var supportedOperations: Set<IntelligenceOperation> { get }

    /// Pull separate tasks out of a brain dump.
    func extractTasks(_ request: TaskExtractionRequest) async throws -> Validated<TaskExtraction>

    /// Break one task into an ordered ladder of steps.
    func decompose(_ request: DecompositionRequest) async throws -> Validated<Decomposition>

    /// Produce the single concrete first step for one task.
    func nextAction(_ request: NextActionRequest) async throws -> Validated<ProposedAction>

    /// Guess how long one task will take.
    func estimateDuration(
        _ request: DurationEstimateRequest
    ) async throws -> Validated<DurationEstimate>

    /// Produce a smaller step for someone who is stuck.
    func simplify(_ request: SimplificationRequest) async throws -> Validated<ProposedAction>
}

extension IntelligenceProvider {

    /// Whether this provider is worth asking about a given operation.
    public func supports(_ operation: IntelligenceOperation) -> Bool {
        supportedOperations.contains(operation)
    }
}
