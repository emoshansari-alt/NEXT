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

    public init(
        id: TaskID,
        title: String,
        createdAt: Date,
        status: TaskStatus = .active,
        deadline: Date? = nil,
        importance: Importance = .normal
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.status = status
        self.deadline = deadline
        self.importance = importance
    }

    /// Whether the deadline has already passed at the given instant.
    /// Takes `now` as a parameter because `NextKit` never reads the clock (D-007).
    public func isOverdue(at now: Date) -> Bool {
        guard let deadline else { return false }
        return deadline < now
    }
}
