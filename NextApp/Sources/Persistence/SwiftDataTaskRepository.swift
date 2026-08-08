import Foundation
import NextKit
import SwiftData

/// The real store: `TaskRepository` backed by SwiftData.
///
/// A `@ModelActor`, which is what makes the protocol's `async` signature honest rather than
/// decorative. `ModelContext` is not `Sendable`; it belongs to whichever actor owns it, and this
/// actor owns one. Every call from the outside is therefore a hop onto this actor, off the main
/// thread, and the UI never blocks on a query.
///
/// Everything crossing the boundary is a `TaskItem` value. No `StoredTask` and no
/// `ModelContext` ever escapes — they are not `Sendable` and letting one out would put a
/// reference to the store's private context somewhere it could be used from another thread.
@ModelActor
actor SwiftDataTaskRepository: TaskRepository {

    // MARK: Reading

    func fetchAll() throws -> [TaskItem] {
        try rows(matching: nil).map(\.domainValue)
    }

    func fetch(id: TaskID) throws -> TaskItem? {
        try row(for: id.rawValue)?.domainValue
    }

    func fetch(status: TaskStatus) throws -> [TaskItem] {
        // Compared against the stored raw value rather than the enum: `#Predicate` over an
        // enum is fragile, and this is the most frequent read in the app.
        let raw = status.rawValue
        return try rows(matching: #Predicate<StoredTask> { $0.statusRaw == raw })
            .map(\.domainValue)
    }

    // MARK: Writing

    func upsert(_ task: TaskItem) throws {
        if let existing = try row(for: task.id.rawValue) {
            existing.apply(task)
        } else {
            modelContext.insert(StoredTask(task: task))
        }
        try modelContext.save()
    }

    func delete(id: TaskID) throws {
        // Deleting something that is not there is a no-op, not an error — the contract says so,
        // because delete is reachable from a stale widget snapshot or a notification action.
        guard let existing = try row(for: id.rawValue) else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }

    // MARK: Fetching

    /// Rows in contract order: oldest first, ties broken by identifier.
    ///
    /// The sort is applied by the store rather than by the caller, and both keys are required.
    /// `createdAt` alone is not a total order — tasks captured from a single brain dump share a
    /// creation instant exactly — and an unordered remainder would leak the store's own
    /// iteration order into the ranking engine, which is a pure function of the list it is
    /// handed. Two launches with identical data could then show different recommendations.
    private func rows(matching predicate: Predicate<StoredTask>?) throws -> [StoredTask] {
        var descriptor = FetchDescriptor<StoredTask>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\StoredTask.createdAt, order: .forward),
                SortDescriptor(\StoredTask.identifier, order: .forward)
            ]
        )
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor)
    }

    private func row(for identifier: String) throws -> StoredTask? {
        var descriptor = FetchDescriptor<StoredTask>(
            predicate: #Predicate<StoredTask> { $0.identifier == identifier }
        )
        descriptor.fetchLimit = 1
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).first
    }
}
