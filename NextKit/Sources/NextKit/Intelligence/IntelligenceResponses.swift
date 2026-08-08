import Foundation

// The wire shapes a provider returns.
//
// ## These types are untrusted, and they are permissive on purpose
//
// PRODUCT_SPEC.md §6 requires typed structured output rather than prose to be regex-parsed, and
// these are those types. But every field is optional and every enumerated field is a raw
// `String`, which looks like sloppy modelling and is the opposite.
//
// A wire type has one job: represent what actually arrived, including the wrong things. If
// `title` were non-optional, a response missing it would fail inside `JSONDecoder` and surface
// as "malformed JSON" — true, useless, and indistinguishable from a truncated stream. If
// `importance` were an `Importance`, an unknown value would do the same. Making the transport
// permissive is what lets `ResponseValidator` say *which field* was wrong and *which item* it
// belonged to, which is the difference between a diagnosable failure and a shrug.
//
// So: decoding proves the bytes are JSON of roughly this shape. Nothing more. Everything that
// makes a response *acceptable* is decided by the validator, and no value from these types
// reaches the task database without passing through it.

/// The response to `extractTasks`. Mirrors the shape illustrated in PRODUCT_SPEC.md §6.
public struct TaskExtractionResponse: Codable, Hashable, Sendable {

    public var tasks: [ExtractedTask]?

    public init(tasks: [ExtractedTask]? = nil) {
        self.tasks = tasks
    }
}

/// One task a provider believes it found in the user's text.
public struct ExtractedTask: Codable, Hashable, Sendable {

    public var title: String?

    /// ISO-8601. Either a full instant (`2026-08-13T23:59:00Z`) or a bare date (`2026-08-13`),
    /// which is read as the start of that day in UTC.
    public var deadline: String?

    public var estimatedMinutes: Int?

    /// The raw string. Validated against `Importance`, never mapped onto the nearest match.
    public var importance: String?

    /// Per-field confidence. Required — see `FieldConfidence`.
    public var confidence: FieldConfidence?

    public init(
        title: String? = nil,
        deadline: String? = nil,
        estimatedMinutes: Int? = nil,
        importance: String? = nil,
        confidence: FieldConfidence? = nil
    ) {
        self.title = title
        self.deadline = deadline
        self.estimatedMinutes = estimatedMinutes
        self.importance = importance
        self.confidence = confidence
    }
}

/// How sure the provider is, field by field.
///
/// Per-field rather than one number for the whole task, because the fields fail differently.
/// "chem thing thurs" gives a title anyone would accept and a date that could easily be next
/// Thursday: a single blended confidence would either hide the doubt about the date or throw
/// away a perfectly good title. The Capture Confirmation screen asks about the field that is
/// actually uncertain, and only that field.
public struct FieldConfidence: Codable, Hashable, Sendable {

    public var title: Double?
    public var deadline: Double?
    public var duration: Double?

    public init(title: Double? = nil, deadline: Double? = nil, duration: Double? = nil) {
        self.title = title
        self.deadline = deadline
        self.duration = duration
    }
}

/// The response to `decompose`.
public struct DecompositionResponse: Codable, Hashable, Sendable {

    public var steps: [ProposedStep]?

    public init(steps: [ProposedStep]? = nil) {
        self.steps = steps
    }
}

/// One step of a proposed decomposition.
public struct ProposedStep: Codable, Hashable, Sendable {

    public var text: String?
    public var estimatedMinutes: Int?
    public var confidence: Double?

    public init(text: String? = nil, estimatedMinutes: Int? = nil, confidence: Double? = nil) {
        self.text = text
        self.estimatedMinutes = estimatedMinutes
        self.confidence = confidence
    }
}

/// The response to `nextAction`.
public struct NextActionResponse: Codable, Hashable, Sendable {

    public var nextAction: String?
    public var estimatedMinutes: Int?
    public var confidence: Double?

    public init(
        nextAction: String? = nil, estimatedMinutes: Int? = nil, confidence: Double? = nil
    ) {
        self.nextAction = nextAction
        self.estimatedMinutes = estimatedMinutes
        self.confidence = confidence
    }
}

/// The response to `estimateDuration`.
public struct DurationEstimateResponse: Codable, Hashable, Sendable {

    public var estimatedMinutes: Int?
    public var confidence: Double?

    public init(estimatedMinutes: Int? = nil, confidence: Double? = nil) {
        self.estimatedMinutes = estimatedMinutes
        self.confidence = confidence
    }
}

/// The response to `simplify`.
///
/// Note what a provider cannot return: framing. Rescue's one-line framing — "Start here.",
/// "Forget the rest of it for now." — is generated deterministically by `RescueFraming` and is
/// not expressible in this type. Tone is a product invariant (PRODUCT_SPEC.md §3, P5), and an
/// invariant delegated to a model is not one. A provider supplies the *step*; NEXT supplies its
/// own voice.
public struct SimplificationResponse: Codable, Hashable, Sendable {

    public var step: String?
    public var estimatedMinutes: Int?
    public var confidence: Double?

    public init(step: String? = nil, estimatedMinutes: Int? = nil, confidence: Double? = nil) {
        self.step = step
        self.estimatedMinutes = estimatedMinutes
        self.confidence = confidence
    }
}
