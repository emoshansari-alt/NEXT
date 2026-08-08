/// A field in a provider response.
///
/// Named rather than described in a string so that a failure can be reasoned about in code —
/// the app layer can decide that a bad deadline is worth a different recovery from a bad title
/// without parsing an error message.
public enum ResponseField: String, Hashable, Sendable, CaseIterable, Codable {

    /// The top-level task array.
    case tasks

    /// The top-level step array.
    case steps

    case title
    case deadline
    case estimatedMinutes
    case importance

    /// The confidence attached to a title, deadline or duration.
    case titleConfidence
    case deadlineConfidence
    case durationConfidence

    /// One generated instruction: a decomposition step or a Rescue simplification.
    case step

    /// A generated next action.
    case nextAction

    /// A standalone duration estimate.
    case minutes

    /// The confidence attached to a standalone generated value.
    case confidence
}

/// Why a provider response was refused.
///
/// Every case is *wholesale*. There is no "partially valid" outcome and no way to express one:
/// a response with one bad task is discarded entirely, so the user's database can never end up
/// holding the half of a response that happened to parse (PRODUCT_SPEC.md §6).
///
/// ## No case carries text
///
/// Deliberate, and the reason `unparseableDate` does not include the string it failed to parse.
/// A validation failure is exactly the kind of thing that ends up in a log line, a breadcrumb or
/// a crash report, and PRIVACY.md forbids task text appearing in any of them. The field name and
/// the item index locate the problem precisely enough to fix it; the value itself is the one
/// piece of the picture that must not travel.
public enum ValidationFailure: Error, Hashable, Sendable {

    /// The response was well-formed and contained nothing.
    case emptyResponse(IntelligenceOperation)

    /// More items than the limits allow.
    case tooManyItems(IntelligenceOperation, count: Int, limit: Int)

    /// A field the response cannot do without was absent or blank.
    case missingRequiredField(ResponseField, itemIndex: Int?)

    /// A string field exceeded its bound.
    case fieldTooLong(ResponseField, itemIndex: Int?, length: Int, limit: Int)

    /// A date field was not a date.
    case unparseableDate(ResponseField, itemIndex: Int?)

    /// A date field was a date, but not one a student could plausibly have.
    case implausibleDate(ResponseField, itemIndex: Int?)

    /// A duration outside the plausible bounds.
    case implausibleDuration(ResponseField, itemIndex: Int?, minutes: Int)

    /// An enumerated field carried a value NEXT does not have.
    case unknownEnumValue(ResponseField, itemIndex: Int?)

    /// A confidence outside `0...1`. Note that a *low* confidence is not this: see
    /// `FieldConfirmation`.
    case confidenceOutOfRange(ResponseField, itemIndex: Int?)

    /// Generated text NEXT will not say. Shaming or clinical framing is a product defect
    /// (invariant P5, PRODUCT_SPEC.md §1), so it fails the gate rather than reaching a screen.
    case unacceptableTone(ResponseField, itemIndex: Int?)

    /// Which item of a list the failure belongs to, if it belongs to one.
    public var itemIndex: Int? {
        switch self {
        case .emptyResponse, .tooManyItems:
            nil
        case .missingRequiredField(_, let index),
             .fieldTooLong(_, let index, _, _),
             .unparseableDate(_, let index),
             .implausibleDate(_, let index),
             .implausibleDuration(_, let index, _),
             .unknownEnumValue(_, let index),
             .confidenceOutOfRange(_, let index),
             .unacceptableTone(_, let index):
            index
        }
    }

    /// The field at fault, if the failure is about one field rather than the whole response.
    public var field: ResponseField? {
        switch self {
        case .emptyResponse, .tooManyItems:
            nil
        case .missingRequiredField(let field, _),
             .fieldTooLong(let field, _, _, _),
             .unparseableDate(let field, _),
             .implausibleDate(let field, _),
             .implausibleDuration(let field, _, _),
             .unknownEnumValue(let field, _),
             .confidenceOutOfRange(let field, _),
             .unacceptableTone(let field, _):
            field
        }
    }
}
