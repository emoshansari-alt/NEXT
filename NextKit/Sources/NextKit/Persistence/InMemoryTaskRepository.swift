import Foundation

/// A complete, working `TaskRepository` that keeps everything in memory.
///
/// Not a mock and not a stub. It implements the whole contract honestly, which is what lets the
/// entire domain layer — capture, ranking, transitions, rescue — be exercised at Tier 1 on a
/// machine with no Xcode, and lets SwiftUI previews in `NextApp` run against real data without
/// a store on disk.
///
/// It is an `actor` because `TaskRepository` is `Sendable` and asynchronous: callers can and
/// will reach it from several tasks at once — a view model refreshing while a notification
/// action completes something, say — and mutable state shared that way has to be serialised
/// somewhere. An actor is the smallest correct answer, and it costs nothing at the call site
/// because the protocol was already `await`.
public actor InMemoryTaskRepository: TaskRepository {

    /// Keyed by identifier so `upsert` and `delete` are single operations rather than searches.
    /// The order tasks come back in is imposed on read (see `ordered(_:)`), never inherited
    /// from this dictionary — hash order varies between runs and would leak straight into the
    /// ranking engine's input.
    private var tasksByID: [TaskID: TaskItem]

    /// Creates a store, optionally pre-loaded.
    ///
    /// Later duplicates win, matching `upsert`, so seeding and writing behave the same way.
    public init(_ tasks: [TaskItem] = []) {
        tasksByID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    // MARK: - Reading

    public func fetchAll() async throws -> [TaskItem] {
        Self.ordered(tasksByID.values)
    }

    public func fetch(id: TaskID) async throws -> TaskItem? {
        tasksByID[id]
    }

    public func fetch(status: TaskStatus) async throws -> [TaskItem] {
        Self.ordered(tasksByID.values.filter { $0.status == status })
    }

    // MARK: - Writing

    public func upsert(_ task: TaskItem) async throws {
        tasksByID[task.id] = task
    }

    /// Atomic by construction: the batch is staged in a copy and swapped in at the end, so a
    /// caller cancelled midway cannot leave half a brain dump behind. Nothing here throws, but
    /// the shape matters — it is the contract this store is promising to keep, and the next
    /// implementation of it will be one where writes really can fail.
    public func upsert(_ tasks: [TaskItem]) async throws {
        guard !tasks.isEmpty else { return }

        var staged = tasksByID
        for task in tasks { staged[task.id] = task }
        tasksByID = staged
    }

    public func delete(id: TaskID) async throws {
        tasksByID.removeValue(forKey: id)
    }

    // MARK: - Ordering

    /// The contract's order: oldest first, ties broken by identifier.
    ///
    /// The identifier tie-break is what makes this a *total* order rather than merely a sort.
    /// Tasks captured from one brain dump share a creation instant exactly, so without it the
    /// relative order of that group would be left to the sort's discretion.
    private static func ordered(_ tasks: some Sequence<TaskItem>) -> [TaskItem] {
        tasks.sorted { left, right in
            if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
            return left.id.rawValue < right.id.rawValue
        }
    }
}
