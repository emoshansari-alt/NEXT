import Foundation

/// The provider that works on a train.
///
/// No model, no network, no API key, no consent prompt, no hardware requirement. PRODUCT_SPEC.md
/// §6 requires NEXT to stay genuinely useful when there is no internet, the provider is down, the
/// user declined intelligent features, the response failed validation, or the device cannot run a
/// model at all. This is the thing that makes that true rather than aspirational, and
/// ARCHITECTURE.md §5 puts it last in the chain: it is always present and always answers.
///
/// ## Its discipline is refusing to guess
///
/// Everything here is a shallow, deterministic reading of the user's own words. It splits text it
/// can split, recognises a handful of date phrases exactly, and reports low confidence as low
/// confidence. It never infers importance, never invents a duration, and never produces a
/// deadline out of a phrase it does not understand — "practice at 6" comes back as a task called
/// "Practice at 6" with no date, because six in the morning and six in the evening are different
/// promises and NEXT was not told which.
///
/// ## It goes through the same gate as everything else
///
/// Its answers are built as ordinary wire responses and handed to `ResponseValidator` exactly as
/// a model's bytes would be. That round trip through a JSON-shaped value looks redundant for a
/// provider that authored the data itself, and it is not: the gate is only non-bypassable if
/// nothing bypasses it, and a bug in this file must be caught by the same net as a bug in a
/// vendor's model.
public struct TemplateFallbackProvider: IntelligenceProvider {

    // MARK: Confidence in a template
    //
    // How much a keyword read of a title is worth. These are judgements, stated once, in the
    // open, next to each other so the ordering is reviewable.

    /// A title whose kind of work NEXT recognised. A shallow read, but a real signal, and above
    /// the confirmation threshold: "Chemistry worksheet" really does start with opening the
    /// worksheet.
    static let recognisedWorkConfidence = 0.8

    /// A title that said nothing NEXT understood. The generic ladder is honest rather than
    /// right, so it sits below the threshold and is offered as a suggestion to confirm.
    static let genericWorkConfidence = 0.4

    /// A title carried through from the user's own text, unchanged apart from trimming.
    static let verbatimTitleConfidence = 1.0

    /// A title the parser removed a date phrase from. Still the user's words, minus some — a
    /// slightly stronger claim than leaving them alone, so slightly less than certain.
    static let trimmedTitleConfidence = 0.9

    private let validator: ResponseValidator

    public init(validator: ResponseValidator = ResponseValidator()) {
        self.validator = validator
    }

    /// Four of the five. See `estimateDuration`.
    public var supportedOperations: Set<IntelligenceOperation> {
        [.extractTasks, .decompose, .nextAction, .simplify]
    }

    // MARK: - Extraction

    public func extractTasks(
        _ request: TaskExtractionRequest
    ) async throws -> Validated<TaskExtraction> {
        let extracted = BrainDumpSplitter.fragments(in: request.text).map { fragment in
            let reading = DatePhraseParser.read(
                fragment, now: request.now, timeZone: request.timeZone
            )

            return ExtractedTask(
                title: Self.tidied(reading.remainingText),
                deadline: reading.date.map(Self.iso8601),
                // Neither of these is ever filled in. A duration cannot be read off a title
                // without guessing, and importance is the user's judgement about their own
                // work, not a field for NEXT to complete on their behalf.
                estimatedMinutes: nil,
                importance: nil,
                confidence: FieldConfidence(
                    title: reading.date == nil
                        ? Self.verbatimTitleConfidence
                        : Self.trimmedTitleConfidence,
                    deadline: reading.confidence,
                    duration: nil
                )
            )
        }

        return try validator.validated(
            TaskExtractionResponse(tasks: extracted), now: request.now
        )
    }

    // MARK: - Steps

    public func decompose(
        _ request: DecompositionRequest
    ) async throws -> Validated<Decomposition> {
        let ladder = Self.ladder(for: request.title)

        let steps = ladder.texts.prefix(max(1, request.maxSteps)).map {
            ProposedStep(text: $0, estimatedMinutes: nil, confidence: ladder.confidence)
        }

        return try validator.validated(DecompositionResponse(steps: Array(steps)))
    }

    public func nextAction(
        _ request: NextActionRequest
    ) async throws -> Validated<ProposedAction> {
        let ladder = Self.ladder(for: request.title)

        return try validator.validated(
            NextActionResponse(
                nextAction: ladder.texts.first,
                estimatedMinutes: nil,
                confidence: ladder.confidence
            )
        )
    }

    /// The smallest physical step for a task, for someone who is stuck.
    ///
    /// The `path` is not used, and that is not an oversight. What differs between the four
    /// Rescue doors is the framing around the step — "Start here.", "Forget the rest of it for
    /// now.", "Make the deal tiny." — and that copy is generated deterministically by
    /// `RescueFraming`, in NEXT's own voice, never by a provider (see `SimplificationResponse`).
    /// What this layer supplies is the step, and the smallest real step is the smallest real
    /// step whichever door the user came through. Inventing four different answers to look
    /// clever would make them four different qualities of answer.
    public func simplify(
        _ request: SimplificationRequest
    ) async throws -> Validated<ProposedAction> {
        let ladder = Self.ladder(for: request.title)

        return try validator.validated(
            SimplificationResponse(
                step: ladder.texts.first,
                estimatedMinutes: nil,
                confidence: ladder.confidence
            )
        )
    }

    // MARK: - The one it will not do

    /// Declines, every time.
    ///
    /// There is no deterministic answer to "how long will this take". A title carries no
    /// information about it, and a number invented here would be worse than no number at all: it
    /// would drive the time-budget filter, the Focus timer and Minimum Win, all of which treat a
    /// duration as something the user told them. An unestimated task is already handled honestly
    /// everywhere in NEXT — unknown duration means "might fit", not "does not fit"
    /// (`TaskItem.estimatedMinutes`) — so declining costs the product nothing and keeps
    /// invariant P3 intact.
    ///
    /// Callers do not have to discover this by catching: `supportedOperations` says so up front.
    public func estimateDuration(
        _ request: DurationEstimateRequest
    ) async throws -> Validated<DurationEstimate> {
        throw IntelligenceError.unsupported(.estimateDuration)
    }

    // MARK: - Templates

    private struct Ladder {
        let texts: [String]
        let confidence: Double
    }

    /// The ordered steps for a title, and how much they are worth.
    ///
    /// Reuses `WorkKind` and `StepShrinker.genericSteps` rather than restating them.
    /// ARCHITECTURE.md §10 forbids duplicated business logic, and Rescue's ladder and this one
    /// must not be allowed to drift into two slightly different opinions about how to start an
    /// essay.
    private static func ladder(for title: String) -> Ladder {
        if let kind = WorkKind.inferred(fromTitle: title) {
            return Ladder(texts: kind.firstSteps, confidence: recognisedWorkConfidence)
        }
        return Ladder(
            texts: StepShrinker.genericSteps.map(\.text), confidence: genericWorkConfidence
        )
    }

    // MARK: - Text

    /// Trims a fragment and capitalises its first letter, and does nothing else to it.
    ///
    /// No title casing, no punctuation stripping, no spelling correction. "finish the stupid
    /// history slides" becomes "Finish the stupid history slides", because it is the user's list
    /// and NEXT is not editing it.
    private static func tidied(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }

    /// Renders an instant the way a provider would put it on the wire, so that it goes through
    /// exactly the same parsing and sanity checks on the way back in.
    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
