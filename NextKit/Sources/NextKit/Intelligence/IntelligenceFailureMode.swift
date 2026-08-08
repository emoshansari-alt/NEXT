/// The eight ways a provider response goes wrong.
///
/// Not a catalogue of everything imaginable — a list of what has to be *survivable*. Each mode
/// is something a real language model does routinely, and each one has a specific way of being
/// dangerous if it reaches the task database unexamined. They exist as a named type rather than
/// as a pile of test fixtures so that the app layer can exercise its own recovery paths against
/// the same eight, and so that adding a ninth is a visible change.
///
/// Order below is roughly "how early it fails": transport, then parsing, then content.
public enum IntelligenceFailureMode: String, Hashable, Sendable, CaseIterable, Codable {

    /// No answer arrives. The commonest failure of all, and the one most likely to happen on a
    /// train, which is exactly where a student opens this app.
    case timeout

    /// Bytes that are not JSON — a truncated stream, a stray preamble, a trailing comma.
    case malformedJSON

    /// Valid JSON that says nothing. Dangerous because it looks like success: a capture that
    /// silently produces no tasks reads to the user as "the app ate what I typed".
    case emptyResponse

    /// A date no student is working to. The subtle one: a deadline in the year 3000 is never
    /// urgent, so the task would sink in the ranking and quietly never be recommended again.
    case impossibleDate

    /// A duration outside anything a single task takes. Poisons the time-budget filter, Focus,
    /// and Minimum Win all at once.
    case unreasonableDuration

    /// A field the response cannot do without — most often the title.
    case missingRequiredField

    /// A value in an enumerated field that NEXT does not have, such as an importance level
    /// borrowed from some other product's vocabulary.
    case invalidEnum

    /// Several items, most of them fine, one of them not. The mode that tests whether failure is
    /// genuinely wholesale, because it is the one where applying "just the good ones" is
    /// tempting and wrong.
    case partialResponse

    /// The operations this mode can meaningfully be produced for.
    ///
    /// Two of the eight are shape-specific and say so rather than pretending. A decomposition
    /// has no date field, so `impossibleDate` has nowhere to live in one; a next action is a
    /// single value, so it cannot be `partialResponse`. Asking for an inapplicable combination
    /// is an error rather than a silently different failure.
    public var applicableOperations: Set<IntelligenceOperation> {
        switch self {
        case .timeout, .malformedJSON, .unreasonableDuration, .missingRequiredField:
            Set(IntelligenceOperation.allCases)

        case .emptyResponse, .partialResponse:
            // Only a list-shaped response has an empty state, or a partial one.
            [.extractTasks, .decompose]

        case .impossibleDate, .invalidEnum:
            // Only extraction carries a date or an enumerated field.
            [.extractTasks]
        }
    }
}
