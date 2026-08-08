import Foundation

// The trusted side of the boundary.
//
// Every type here has already been through `ResponseValidator`. Where the wire types are all
// optionals and raw strings, these are exact: a `ProposedTask` has a title because a task
// without one was rejected, and its `Importance` is an `Importance` because an unknown value
// never got this far.
//
// "Proposed" rather than "extracted" is the honest word. Passing validation makes a value
// *safe*, not *true*. Whether the user accepts it is a separate question, answered on the
// Capture Confirmation screen (PRODUCT_SPEC.md §4.6).

/// A set of tasks a provider found in one piece of text.
public struct TaskExtraction: Hashable, Sendable {

    public let tasks: [ProposedTask]

    public init(tasks: [ProposedTask]) {
        self.tasks = tasks
    }
}

/// One task, validated, not yet accepted by the user.
public struct ProposedTask: Hashable, Sendable {

    /// Non-optional: a task without a title is not a task, and the validator rejects it.
    public let title: String

    public let titleConfidence: Confidence

    /// `nil` means the provider found no deadline — which is a real answer, not a gap. An
    /// undated task is an ordinary thing to have, and guessing rather than admitting it is the
    /// defect PRODUCT_SPEC.md §4.6 exists to prevent.
    public let deadline: ProposedDeadline?

    public let duration: ProposedDuration?

    /// Defaults to `.normal` when the provider said nothing. Importance is the user's judgement
    /// about their own work, and there is no honest way to infer it from a fragment of text.
    public let importance: Importance

    public init(
        title: String,
        titleConfidence: Confidence,
        deadline: ProposedDeadline? = nil,
        duration: ProposedDuration? = nil,
        importance: Importance = .normal
    ) {
        self.title = title
        self.titleConfidence = titleConfidence
        self.deadline = deadline
        self.duration = duration
        self.importance = importance
    }
}

/// A deadline a provider believes it read, with how sure it is.
///
/// The date and the confidence are one value because they are only meaningful together. A date
/// on its own is a claim of certainty, and this type makes that claim impossible to express by
/// accident.
public struct ProposedDeadline: Hashable, Sendable {

    public let date: Date
    public let confidence: Confidence

    public init(date: Date, confidence: Confidence) {
        self.date = date
        self.confidence = confidence
    }
}

/// A duration a provider believes in, with how sure it is.
public struct ProposedDuration: Hashable, Sendable {

    public let minutes: Int
    public let confidence: Confidence

    public init(minutes: Int, confidence: Confidence) {
        self.minutes = minutes
        self.confidence = confidence
    }
}

/// An ordered ladder of steps for one task.
public struct Decomposition: Hashable, Sendable {

    public let steps: [ProposedAction]

    public init(steps: [ProposedAction]) {
        self.steps = steps
    }
}

/// One concrete thing to do.
///
/// The validated counterpart of a decomposition step, a next action and a Rescue
/// simplification — three operations that all answer the same question, so they share one
/// answer type rather than three identical ones.
public struct ProposedAction: Hashable, Sendable {

    public let text: String

    /// Present only when the provider had a basis for it. `nil` means unknown, never "instant" —
    /// the same rule `TaskItem.estimatedMinutes` follows.
    public let estimatedMinutes: Int?

    public let confidence: Confidence

    public init(text: String, estimatedMinutes: Int? = nil, confidence: Confidence) {
        self.text = text
        self.estimatedMinutes = estimatedMinutes
        self.confidence = confidence
    }
}

/// A standalone duration estimate.
public struct DurationEstimate: Hashable, Sendable {

    public let minutes: Int
    public let confidence: Confidence

    public init(minutes: Int, confidence: Confidence) {
        self.minutes = minutes
        self.confidence = confidence
    }
}

/// A field whose value is valid but not certain enough to act on unasked.
///
/// This type is the whole distinction the module turns on. A low confidence is **not** a
/// validation failure — the data is well-formed and probably right. It is a request for one tap
/// on the Capture Confirmation screen, because PRODUCT_SPEC.md §4.6 says an ambiguous deadline
/// asks rather than invents certainty.
///
/// The proposed value is deliberately not duplicated here: it is still sitting in the validated
/// response at `itemIndex`, where the confirmation screen reads it to show the user what it is
/// about to write. Copying it would create two places for it to disagree.
public struct FieldConfirmation: Hashable, Sendable {

    /// Which item of the response, or `0` for a response that is a single value.
    public let itemIndex: Int

    public let field: ResponseField

    /// How sure the provider was. Shown to nobody, but it is what the threshold was compared
    /// against, and a support question about "why did it ask me this" is answerable with it.
    public let confidence: Confidence

    public init(itemIndex: Int, field: ResponseField, confidence: Confidence) {
        self.itemIndex = itemIndex
        self.field = field
        self.confidence = confidence
    }
}
