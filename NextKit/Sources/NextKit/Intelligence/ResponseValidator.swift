import Foundation

/// A value that has been through the gate.
///
/// ## Why this type exists at all
///
/// PRODUCT_SPEC.md §6: "Every response is validated before any state mutation. No AI response
/// can corrupt the local task database." A comment saying so is a convention. This is the
/// enforcement.
///
/// `Validated` has no public initialiser — its only initialiser is `fileprivate`, so the sole
/// place in the entire program that can produce one is `ResponseValidator`, immediately below.
/// Every `IntelligenceProvider` method returns `Validated<…>`, which means a provider written
/// in `NextApp` — a cloud client, an on-device client, anything added later — *cannot* return
/// a value at all without first handing its response to the validator. The gate is not something
/// callers are trusted to remember; it is the only door in the wall.
///
/// ## Validated is not the same as confirmed
///
/// `confirmations` lists fields that passed validation and are still not certain enough to act
/// on unasked. That is a completely different thing from a failure, and the two must never be
/// conflated: a rejected response yields nothing, whereas an uncertain field yields good data
/// plus a question for the user (PRODUCT_SPEC.md §4.6).
///
/// ## Uncertain is also not the same as inferred
///
/// `inferences` is the wider set, and the two are not interchangeable. Every deadline and every
/// duration a provider supplies is an inference, however sure the provider was; only the
/// unconvincing ones become confirmations. PRODUCT_SPEC.md §4.6 opens with "Every consequential
/// AI inference is confirmable — deadlines especially" and narrows to ambiguity afterwards, so a
/// module that recorded only the ambiguous ones would leave the app unable to satisfy the first
/// sentence: a date read at 0.9 would reach the Today screen indistinguishable from one the user
/// typed.
public struct Validated<Value: Hashable & Sendable>: Hashable, Sendable {

    /// The trusted value.
    public let value: Value

    /// Fields the user should confirm before they are treated as authoritative,
    /// ordered by item and then by field so the confirmation screen is stable between runs.
    public let confirmations: [FieldConfirmation]

    /// Fields no human supplied, ordered by item and then by field for the same reason.
    ///
    /// A superset of the fields named in `confirmations`, restricted to the ones a provider
    /// invents rather than reads off the user's own words: deadlines and durations.
    public let inferences: [InferredField]

    fileprivate init(
        value: Value,
        confirmations: [FieldConfirmation],
        inferences: [InferredField] = []
    ) {
        self.value = value
        self.confirmations = confirmations
        self.inferences = inferences
    }

    /// Whether anything here needs a human before it is acted on.
    public var requiresConfirmation: Bool { !confirmations.isEmpty }

    /// The fields of one item awaiting confirmation.
    public func unconfirmedFields(ofItem index: Int) -> Set<ResponseField> {
        Set(confirmations.lazy.filter { $0.itemIndex == index }.map(\.field))
    }

    /// The fields of one item that came from a provider rather than from the user.
    ///
    /// Empty for a task whose only content is the title the user typed. Non-empty for every
    /// deadline and duration, including the confident ones `unconfirmedFields(ofItem:)` omits.
    public func inferredFields(ofItem index: Int) -> Set<ResponseField> {
        Set(inferences.lazy.filter { $0.itemIndex == index }.map(\.field))
    }
}

/// The mandatory gate between a provider's answer and the user's data.
///
/// Everything it enforces comes straight from PRODUCT_SPEC.md §6 and ARCHITECTURE.md §5:
/// required fields present, enums in range, dates parseable *and* sane, durations within
/// plausible bounds, string lengths bounded, confidence within `0...1`. Two properties matter
/// more than the individual rules:
///
/// **Failure is wholesale.** The first problem found rejects the entire response. There is no
/// mechanism for applying the good half — the return type cannot express it — so a brain dump
/// where one task carries a hallucinated year cannot leave four tasks in the database and a
/// mystery.
///
/// **Uncertainty is not failure.** A deadline the provider is 40% sure of is *valid data*. It
/// validates, it is carried through, and it is flagged for confirmation. Rejecting it would lose
/// information the user could have corrected in one tap; writing it silently would be the
/// invention of certainty that PRODUCT_SPEC.md §4.6 forbids.
///
/// Pure: `now` is a parameter, never a clock read (DECISIONS.md D-007).
public struct ResponseValidator: Sendable {

    public let limits: ValidationLimits

    public init(limits: ValidationLimits = .default) {
        self.limits = limits
    }

    // MARK: - Decoding

    /// Turns raw bytes into a wire type, or reports that they were not that shape.
    ///
    /// The underlying decoding error is deliberately discarded. `DecodingError` descriptions
    /// quote the offending payload, and a malformed model response very often contains a
    /// mangled echo of the prompt — which is the user's task text. PRIVACY.md forbids that text
    /// reaching a log line or a crash report, and an error value is the easiest way for it to
    /// get there.
    public static func decode<Response: Decodable & Sendable>(
        _ type: Response.Type,
        from data: Data,
        operation: IntelligenceOperation
    ) throws(IntelligenceError) -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw .malformedResponse(operation)
        }
    }

    // MARK: - Extraction

    public func validate(
        _ response: TaskExtractionResponse,
        now: Date
    ) throws(ValidationFailure) -> Validated<TaskExtraction> {
        guard let items = response.tasks, !items.isEmpty else {
            throw .emptyResponse(.extractTasks)
        }
        guard items.count <= limits.maxTasksPerResponse else {
            throw .tooManyItems(
                .extractTasks, count: items.count, limit: limits.maxTasksPerResponse
            )
        }

        var tasks: [ProposedTask] = []
        var confirmations: [FieldConfirmation] = []
        var inferences: [InferredField] = []

        for (index, item) in items.enumerated() {
            let task = try validateTask(item, at: index, now: now)
            tasks.append(task)

            // A deadline or a duration is a reading of the user's text, never something they
            // stated in a field, so it is declared here whatever the provider's confidence was.
            // The title is not: it is the user's own words, carried through.
            if task.deadline != nil {
                inferences.append(InferredField(itemIndex: index, field: .deadline))
            }
            if task.duration != nil {
                inferences.append(InferredField(itemIndex: index, field: .estimatedMinutes))
            }

            // Field order here is the order the confirmation screen reads them in. It is fixed
            // rather than derived from a dictionary, because a screen that reshuffles its
            // questions between launches is a screen nobody can learn.
            if task.titleConfidence.value < limits.confirmationThreshold {
                confirmations.append(
                    FieldConfirmation(
                        itemIndex: index, field: .title, confidence: task.titleConfidence
                    )
                )
            }
            if let deadline = task.deadline,
               deadline.confidence.value < limits.confirmationThreshold {
                confirmations.append(
                    FieldConfirmation(
                        itemIndex: index, field: .deadline, confidence: deadline.confidence
                    )
                )
            }
            if let duration = task.duration,
               duration.confidence.value < limits.confirmationThreshold {
                confirmations.append(
                    FieldConfirmation(
                        itemIndex: index,
                        field: .estimatedMinutes,
                        confidence: duration.confidence
                    )
                )
            }
        }

        return Validated(
            value: TaskExtraction(tasks: tasks),
            confirmations: confirmations,
            inferences: inferences
        )
    }

    private func validateTask(
        _ item: ExtractedTask,
        at index: Int,
        now: Date
    ) throws(ValidationFailure) -> ProposedTask {
        // Title. Note what is *not* done here: no tone screening. A title is the user's own
        // words about their own work, and a student can legitimately have "Read the ADHD
        // chapter" on their list. Screening it would be NEXT censoring the user rather than
        // NEXT watching its own mouth.
        let title = try require(item.title, field: .title, item: index)
        try requireLength(title, field: .title, limit: limits.maxTitleLength, item: index)

        let confidence = item.confidence
        let titleConfidence = try requireConfidence(
            confidence?.title, field: .titleConfidence, item: index
        )

        // Importance. Trimmed and lower-cased before matching, because casing is a formatting
        // accident. Anything still unrecognised is refused rather than mapped onto the nearest
        // value: NEXT has two levels on purpose (PRODUCT_SPEC.md §4.8), and deciding that some
        // other product's "high" means "important" would be the validator making that call.
        var importance = Importance.normal
        if let raw = item.importance?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            guard let parsed = Importance(rawValue: raw.lowercased()) else {
                throw .unknownEnumValue(.importance, itemIndex: index)
            }
            importance = parsed
        }

        var deadline: ProposedDeadline?
        if let raw = item.deadline?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let deadlineConfidence = try requireConfidence(
                confidence?.deadline, field: .deadlineConfidence, item: index
            )
            guard let date = Self.parseISO8601(raw) else {
                throw .unparseableDate(.deadline, itemIndex: index)
            }
            guard isPlausible(date, now: now) else {
                throw .implausibleDate(.deadline, itemIndex: index)
            }
            deadline = ProposedDeadline(date: date, confidence: deadlineConfidence)
        }

        var duration: ProposedDuration?
        if let minutes = item.estimatedMinutes {
            let durationConfidence = try requireConfidence(
                confidence?.duration, field: .durationConfidence, item: index
            )
            try requireDuration(minutes, field: .estimatedMinutes, item: index)
            duration = ProposedDuration(minutes: minutes, confidence: durationConfidence)
        }

        return ProposedTask(
            title: title,
            titleConfidence: titleConfidence,
            deadline: deadline,
            duration: duration,
            importance: importance
        )
    }

    // MARK: - Decomposition

    public func validate(
        _ response: DecompositionResponse
    ) throws(ValidationFailure) -> Validated<Decomposition> {
        guard let items = response.steps, !items.isEmpty else {
            throw .emptyResponse(.decompose)
        }
        guard items.count <= limits.maxStepsPerDecomposition else {
            throw .tooManyItems(
                .decompose, count: items.count, limit: limits.maxStepsPerDecomposition
            )
        }

        var steps: [ProposedAction] = []
        var confirmations: [FieldConfirmation] = []
        var inferences: [InferredField] = []

        for (index, item) in items.enumerated() {
            let action = try validateAction(
                text: item.text,
                estimatedMinutes: item.estimatedMinutes,
                rawConfidence: item.confidence,
                field: .step,
                item: index
            )
            steps.append(action)

            if action.estimatedMinutes != nil {
                inferences.append(InferredField(itemIndex: index, field: .estimatedMinutes))
            }

            if action.confidence.value < limits.confirmationThreshold {
                confirmations.append(
                    FieldConfirmation(
                        itemIndex: index, field: .step, confidence: action.confidence
                    )
                )
            }
        }

        return Validated(
            value: Decomposition(steps: steps),
            confirmations: confirmations,
            inferences: inferences
        )
    }

    // MARK: - Single generated actions

    public func validate(
        _ response: NextActionResponse
    ) throws(ValidationFailure) -> Validated<ProposedAction> {
        try validateSingleAction(
            text: response.nextAction,
            estimatedMinutes: response.estimatedMinutes,
            rawConfidence: response.confidence,
            field: .nextAction
        )
    }

    public func validate(
        _ response: SimplificationResponse
    ) throws(ValidationFailure) -> Validated<ProposedAction> {
        try validateSingleAction(
            text: response.step,
            estimatedMinutes: response.estimatedMinutes,
            rawConfidence: response.confidence,
            field: .step
        )
    }

    private func validateSingleAction(
        text: String?,
        estimatedMinutes: Int?,
        rawConfidence: Double?,
        field: ResponseField
    ) throws(ValidationFailure) -> Validated<ProposedAction> {
        let action = try validateAction(
            text: text,
            estimatedMinutes: estimatedMinutes,
            rawConfidence: rawConfidence,
            field: field,
            item: nil
        )

        let confirmations =
            action.confidence.value < limits.confirmationThreshold
            ? [FieldConfirmation(itemIndex: 0, field: field, confidence: action.confidence)]
            : []

        let inferences =
            action.estimatedMinutes == nil
            ? []
            : [InferredField(itemIndex: 0, field: .estimatedMinutes)]

        return Validated(value: action, confirmations: confirmations, inferences: inferences)
    }

    /// The shared rules for any piece of text NEXT would put in front of the user as an
    /// instruction. Unlike a title, this *is* NEXT speaking, so it is screened for tone.
    private func validateAction(
        text: String?,
        estimatedMinutes: Int?,
        rawConfidence: Double?,
        field: ResponseField,
        item: Int?
    ) throws(ValidationFailure) -> ProposedAction {
        let instruction = try require(text, field: field, item: item)
        try requireLength(instruction, field: field, limit: limits.maxStepLength, item: item)
        try requireAcceptableTone(instruction, field: field, item: item)

        let confidence = try requireConfidence(rawConfidence, field: .confidence, item: item)

        if let minutes = estimatedMinutes {
            try requireDuration(minutes, field: .estimatedMinutes, item: item)
        }

        return ProposedAction(
            text: instruction, estimatedMinutes: estimatedMinutes, confidence: confidence
        )
    }

    // MARK: - Duration estimate

    public func validate(
        _ response: DurationEstimateResponse
    ) throws(ValidationFailure) -> Validated<DurationEstimate> {
        guard let minutes = response.estimatedMinutes else {
            throw .missingRequiredField(.minutes, itemIndex: nil)
        }
        try requireDuration(minutes, field: .minutes, item: nil)

        let confidence = try requireConfidence(
            response.confidence, field: .confidence, item: nil
        )

        let confirmations =
            confidence.value < limits.confirmationThreshold
            ? [FieldConfirmation(itemIndex: 0, field: .minutes, confidence: confidence)]
            : []

        // The whole of this response is a number a provider produced, so the whole of it is an
        // inference — including the confident ones, which is exactly the case that would
        // otherwise reach a `TaskItem` looking like the user's own estimate.
        return Validated(
            value: DurationEstimate(minutes: minutes, confidence: confidence),
            confirmations: confirmations,
            inferences: [InferredField(itemIndex: 0, field: .minutes)]
        )
    }

    // MARK: - Shared rules

    /// A present, non-blank string, or a named missing-field failure. Whitespace does not count
    /// as content: a title of three spaces would render as an unidentifiable row.
    private func require(
        _ raw: String?,
        field: ResponseField,
        item: Int?
    ) throws(ValidationFailure) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { throw .missingRequiredField(field, itemIndex: item) }
        return trimmed
    }

    private func requireLength(
        _ text: String,
        field: ResponseField,
        limit: Int,
        item: Int?
    ) throws(ValidationFailure) {
        guard text.count <= limit else {
            throw .fieldTooLong(field, itemIndex: item, length: text.count, limit: limit)
        }
    }

    /// A confidence that is genuinely in `0...1`.
    ///
    /// Two very different kinds of wrong, handled differently on purpose.
    ///
    /// **Out of range is a failure.** `1.4` is not enthusiasm, it is a malformed field, and
    /// clamping it to `1.0` would turn a broken response into a confident-looking one.
    ///
    /// **Absent is not a failure — it is zero.** A provider that supplies a deadline and no
    /// confidence for it has not claimed the deadline is right; it has said nothing. Reading
    /// silence as certainty is exactly the defect this module exists to prevent, and reading it
    /// as a rejection would throw away a whole brain dump over a missing decimal. Reading it as
    /// zero sends the field to the user, which is what PRODUCT_SPEC.md §4.6 asks for.
    ///
    /// This is also what makes the illustrative payload in PRODUCT_SPEC.md §6 — which carries a
    /// duration with no duration confidence — valid, as the authoritative document requires.
    private func requireConfidence(
        _ raw: Double?,
        field: ResponseField,
        item: Int?
    ) throws(ValidationFailure) -> Confidence {
        guard let raw else { return .unstated }
        guard let confidence = Confidence(raw) else {
            throw .confidenceOutOfRange(field, itemIndex: item)
        }
        return confidence
    }

    private func requireDuration(
        _ minutes: Int,
        field: ResponseField,
        item: Int?
    ) throws(ValidationFailure) {
        guard minutes >= limits.minEstimatedMinutes, minutes <= limits.maxEstimatedMinutes else {
            throw .implausibleDuration(field, itemIndex: item, minutes: minutes)
        }
    }

    private func requireAcceptableTone(
        _ text: String,
        field: ResponseField,
        item: Int?
    ) throws(ValidationFailure) {
        let lowered = text.lowercased()
        guard !limits.forbiddenInGeneratedText.contains(where: { lowered.contains($0) }) else {
            throw .unacceptableTone(field, itemIndex: item)
        }
    }

    /// Whether a date is one a student could plausibly be working to.
    ///
    /// Deliberately asymmetric: a year into the past is fine because overdue is a normal state
    /// (invariant P4), while three years into the future is the outer edge of a degree. The
    /// window is anchored on the injected `now`, so the same payload is sane in 2026 and absurd
    /// in 2016 — which is the behaviour a deadline-driven app needs and a clock read could not
    /// give honestly.
    private func isPlausible(_ date: Date, now: Date) -> Bool {
        let offset = date.timeIntervalSince(now)
        return offset >= limits.earliestDeadlineOffset && offset <= limits.latestDeadlineOffset
    }

    // MARK: - The provider-facing form
    //
    // Every provider needs the same two lines — validate, and rewrap a `ValidationFailure` as
    // the `IntelligenceError` its callers handle. Writing them once here means a provider added
    // later cannot get the wrapping subtly wrong, and cannot be tempted to skip it.

    public func validated(
        _ response: TaskExtractionResponse,
        now: Date
    ) throws(IntelligenceError) -> Validated<TaskExtraction> {
        do { return try validate(response, now: now) } catch { throw .validationFailed(error) }
    }

    public func validated(
        _ response: DecompositionResponse
    ) throws(IntelligenceError) -> Validated<Decomposition> {
        do { return try validate(response) } catch { throw .validationFailed(error) }
    }

    public func validated(
        _ response: NextActionResponse
    ) throws(IntelligenceError) -> Validated<ProposedAction> {
        do { return try validate(response) } catch { throw .validationFailed(error) }
    }

    public func validated(
        _ response: SimplificationResponse
    ) throws(IntelligenceError) -> Validated<ProposedAction> {
        do { return try validate(response) } catch { throw .validationFailed(error) }
    }

    public func validated(
        _ response: DurationEstimateResponse
    ) throws(IntelligenceError) -> Validated<DurationEstimate> {
        do { return try validate(response) } catch { throw .validationFailed(error) }
    }

    // MARK: - Dates on the wire

    /// Parses the two ISO-8601 shapes NEXT accepts, and nothing else.
    ///
    /// A full instant (`2026-08-13T23:59:00Z`, with or without fractional seconds) or a bare
    /// date (`2026-08-13`), which is read as the start of that day in UTC. Anything else —
    /// "next Friday", "13/08/2026", a Unix timestamp — is refused rather than guessed at. A
    /// wrong deadline is worse than an absent one, because an absent one gets asked about.
    ///
    /// The formatters are built per call rather than shared. `ISO8601DateFormatter` is a
    /// reference type with mutable options, so a shared instance would be a data race waiting
    /// for the first concurrent capture.
    static func parseISO8601(_ raw: String) -> Date? {
        let optionSets: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime],
            [.withInternetDateTime, .withFractionalSeconds],
            [.withFullDate]
        ]

        for options in optionSets {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}
