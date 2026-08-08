import Foundation

// Requests to an intelligence provider.
//
// ## Privacy is the design constraint, not a comment on it
//
// PRIVACY.md: "An AI request carries only the text required for that one operation. Breaking
// down one task sends that task — never the task list, never completion history, never anything
// about other assignments." Explicitly forbidden in any request: the full task database,
// completion history, rejection history, device identifiers, or any stable user identifier.
//
// That rule is enforced here by *shape*. None of these types has a field that could hold a task
// list, a rejection, a completion, a device identifier — or even a `TaskID`. A caller who wanted
// to send the whole database would have to change one of these types first, which is a reviewable
// act rather than an accident. Correlating a response back to a task is the caller's job, done
// locally, with an identifier that never left the device.
//
// The `init(task:)` convenience initialisers exist for the same reason: the copy from a rich
// `TaskItem` down to the few fields a provider needs happens in exactly one auditable place
// instead of at every call site.

/// Turn unstructured text into separate tasks.
public struct TaskExtractionRequest: Hashable, Sendable, Codable {

    /// Exactly what the user typed or pasted, and nothing else.
    public let text: String

    /// The instant to resolve relative phrases like "tomorrow" against.
    ///
    /// Injected, never read (DECISIONS.md D-007). A provider that reached for the clock here
    /// would make "chem test monday" resolve differently depending on when the test ran.
    public let now: Date

    /// The zone "monday" and "tonight" are meant in.
    ///
    /// There is no default on purpose. The ambient time zone is ambient state, and this module
    /// does not read ambient state any more than it reads the clock.
    public let timeZone: TimeZone

    public init(text: String, now: Date, timeZone: TimeZone) {
        self.text = text
        self.now = now
        self.timeZone = timeZone
    }
}

/// Break one task into steps.
public struct DecompositionRequest: Hashable, Sendable, Codable {

    public let title: String

    /// The user's own estimate, when they gave one. Sent because it changes what a sensible
    /// decomposition looks like: a 20-minute task does not want six steps.
    public let estimatedMinutes: Int?

    /// How many steps are wanted at most.
    public let maxSteps: Int

    public init(title: String, estimatedMinutes: Int?, maxSteps: Int) {
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.maxSteps = maxSteps
    }

    /// The only place a `TaskItem` is narrowed to a decomposition request.
    ///
    /// Note what is dropped: the identifier, creation time, status, deadline, parent, every
    /// prerequisite, and the whole rejection history. None of it would improve a decomposition,
    /// and all of it is about the user rather than about the work.
    public init(task: TaskItem, maxSteps: Int = 6) {
        self.init(title: task.title, estimatedMinutes: task.estimatedMinutes, maxSteps: maxSteps)
    }
}

/// Produce the single concrete first step for one task.
public struct NextActionRequest: Hashable, Sendable, Codable {

    public let title: String

    public init(title: String) {
        self.title = title
    }

    /// See `DecompositionRequest.init(task:maxSteps:)`. The title is the whole of the context.
    public init(task: TaskItem) {
        self.init(title: task.title)
    }
}

/// Guess how long one task will take.
public struct DurationEstimateRequest: Hashable, Sendable, Codable {

    public let title: String

    public init(title: String) {
        self.title = title
    }

    /// Deliberately does not carry the user's existing estimate: asking a provider to improve on
    /// a number the user chose would let inference overwrite the user's own judgement, which
    /// invariant P3 forbids.
    public init(task: TaskItem) {
        self.init(title: task.title)
    }
}

/// Produce a smaller step for someone who is stuck.
public struct SimplificationRequest: Hashable, Sendable, Codable {

    public let title: String

    /// Which of the four Rescue doors the user came through. It changes what a good answer is,
    /// not merely how it is worded.
    public let path: RescuePath

    /// How long the user says they have, when the path asked. `nil` on the three paths that
    /// do not ask (PRODUCT_SPEC.md §4.11).
    public let availableMinutes: Int?

    public init(title: String, path: RescuePath, availableMinutes: Int? = nil) {
        self.title = title
        self.path = path
        self.availableMinutes = availableMinutes
    }

    /// See `DecompositionRequest.init(task:maxSteps:)`.
    ///
    /// The rejection history is conspicuously absent even though it is the one thing a model
    /// might find "useful" here. Sending a record of what someone has avoided, to a provider,
    /// about the day they asked for help, is exactly the transfer PRIVACY.md rules out.
    public init(task: TaskItem, path: RescuePath, availableMinutes: Int? = nil) {
        self.init(title: task.title, path: path, availableMinutes: availableMinutes)
    }
}
