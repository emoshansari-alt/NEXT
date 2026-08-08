import Foundation
import NextKit
import Observation

/// Everything — the screen for seeing and fixing what NEXT already knows.
///
/// Deliberately *not* a second place to decide what to do. That is Today's job, and duplicating
/// it here would put the user back in front of the whole list, which is the state the app exists
/// to get them out of (PRODUCT_SPEC.md §4.7).
///
/// Its actual purpose is repair: a mistyped task, a wrong deadline, something that should never
/// have been captured. Without it, capture is a one-way door.
@MainActor
@Observable
final class EverythingViewModel {

    private(set) var sections: TaskSections
    private(set) var storeFailure: String?

    private let repository: any TaskRepository
    private let timeSource: any TimeSource
    private let calendar: Calendar

    init(
        repository: any TaskRepository,
        timeSource: any TimeSource = SystemTimeSource(),
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.timeSource = timeSource
        self.calendar = calendar
        self.sections = TaskSections(tasks: [], now: timeSource.now, calendar: calendar)
    }

    func load() async {
        do {
            let tasks = try await repository.fetchAll()
            sections = TaskSections(tasks: tasks, now: timeSource.now, calendar: calendar)
            storeFailure = nil
        } catch {
            storeFailure = "NEXT could not open your tasks."
        }
    }

    // MARK: Intents

    func complete(_ task: TaskItem) async {
        await write { try task.completed(at: self.timeSource.now) }
    }

    func reopen(_ task: TaskItem) async {
        await write { try task.reopened(at: self.timeSource.now) }
    }

    func archive(_ task: TaskItem) async {
        await write { try task.archived(at: self.timeSource.now) }
    }

    /// Real deletion, not a hidden tombstone (PRIVACY.md).
    func delete(_ task: TaskItem) async {
        do {
            try await repository.delete(id: task.id)
            await load()
        } catch {
            storeFailure = "NEXT could not delete that."
        }
    }

    private func write(_ transition: () throws -> TaskItem) async {
        do {
            try await repository.upsert(transition())
            await load()
        } catch {
            // Covers both a storage failure and a refused transition — completing something
            // already completed, say, which a stale tap can genuinely produce.
            storeFailure = "NEXT could not save that change."
        }
    }
}
