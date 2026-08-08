import Foundation

/// One thing the user has to do.
///
/// Named `TaskItem`, not `Task`, to avoid colliding with Swift Concurrency's `Task`.
///
/// This is a value type with no persistence framework attached. The SwiftData `@Model` class
/// lives in `NextApp` and maps to and from this type at the repository boundary
/// (DECISIONS.md D-006), which keeps the whole domain layer testable off-device.
public struct TaskItem: Hashable, Sendable, Identifiable {

    // MARK: Identity

    public let id: TaskID

    /// What the user called it. e.g. "History essay".
    public var title: String

    /// When the task entered the system. Supplied by the caller — `NextKit` never reads
    /// the clock itself (DECISIONS.md D-007).
    public let createdAt: Date

    // MARK: State

    public var status: TaskStatus

    // MARK: Ranking inputs

    /// When it is due. `nil` means genuinely undated, not "unknown" — an undated task is a
    /// legitimate thing a student has, and it simply contributes no urgency.
    public var deadline: Date?

    /// How much it matters. Two levels only — see `Importance`.
    public var importance: Importance

    /// Roughly how long it will take. `nil` means not estimated, which is the common case
    /// straight out of a brain dump. An unestimated task is never hidden by a time budget:
    /// unknown duration means "might fit", not "does not fit".
    public var estimatedMinutes: Int?

    /// The concrete first physical step, e.g. "Open the assignment instructions."
    /// Its presence is what makes a task startable — there is nothing left to decide.
    public var nextAction: String?

    /// Tasks that must be finished before this one can begin. While any is outstanding this
    /// task is blocked and will not be recommended.
    public var prerequisiteIDs: [TaskID]

    /// The larger task this one is a step of, if any.
    public var parentID: TaskID?

    /// Every time the user said "Not this", oldest first.
    public var rejections: [Rejection]

    public init(
        id: TaskID,
        title: String,
        createdAt: Date,
        status: TaskStatus = .active,
        deadline: Date? = nil,
        importance: Importance = .normal,
        estimatedMinutes: Int? = nil,
        nextAction: String? = nil,
        prerequisiteIDs: [TaskID] = [],
        parentID: TaskID? = nil,
        rejections: [Rejection] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.status = status
        self.deadline = deadline
        self.importance = importance
        self.estimatedMinutes = estimatedMinutes
        self.nextAction = nextAction
        self.prerequisiteIDs = prerequisiteIDs
        self.parentID = parentID
        self.rejections = rejections
    }

    // MARK: Derived

    /// Whether the deadline has already passed at the given instant.
    /// Takes `now` as a parameter because `NextKit` never reads the clock (D-007).
    public func isOverdue(at now: Date) -> Bool {
        guard let deadline else { return false }
        return deadline < now
    }

    /// The most recent rejection, if the user has ever turned this task down.
    public var latestRejection: Rejection? {
        rejections.max { $0.at < $1.at }
    }

    /// Whether a real first step is recorded. Whitespace does not count — an empty next
    /// action would make the task look startable while leaving the user with nothing to do.
    public var hasConcreteNextAction: Bool {
        guard let nextAction else { return false }
        return !nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether this task fits inside a stated time budget.
    /// An unestimated task always fits — see `estimatedMinutes`.
    public func fits(withinMinutes budget: Int?) -> Bool {
        guard let budget, let estimatedMinutes else { return true }
        return estimatedMinutes <= budget
    }
}
