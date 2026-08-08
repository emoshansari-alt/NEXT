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

    public init(
        id: TaskID,
        title: String,
        createdAt: Date,
        status: TaskStatus = .active
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.status = status
    }
}
