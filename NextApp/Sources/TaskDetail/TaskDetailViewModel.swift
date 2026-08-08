import Foundation
import NextKit
import Observation

/// Task Detail — the one place a captured task can be corrected.
///
/// Edits are held locally and written on save rather than on every keystroke. Capture is
/// deliberately forgiving about accuracy (PRODUCT_SPEC.md §4.5), which means this screen is
/// where accuracy actually happens, and a half-typed title should not be what gets stored if
/// the user changes their mind and backs out.
@MainActor
@Observable
final class TaskDetailViewModel {

    /// The task as stored. Replaced on every successful write.
    private(set) var task: TaskItem

    /// True once the task has been deleted, so the screen can close itself.
    private(set) var isDeleted = false

    private(set) var failure: String?

    // Editable copies.
    var title: String
    var notes: String
    var nextAction: String
    var deadline: Date?
    var estimatedMinutes: Int?
    var importance: Importance

    private let repository: any TaskRepository
    private let timeSource: any TimeSource

    init(
        task: TaskItem,
        repository: any TaskRepository,
        timeSource: any TimeSource = SystemTimeSource()
    ) {
        self.task = task
        self.repository = repository
        self.timeSource = timeSource

        title = task.title
        notes = task.notes
        nextAction = task.nextAction ?? ""
        deadline = task.deadline
        estimatedMinutes = task.estimatedMinutes
        importance = task.importance
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A task with no name is not a task, so saving one is refused rather than silently
    /// storing something the user cannot identify later.
    var canSave: Bool { !trimmedTitle.isEmpty && hasChanges }

    var hasChanges: Bool {
        trimmedTitle != task.title
            || notes != task.notes
            || trimmedNextAction != (task.nextAction ?? "")
            || deadline != task.deadline
            || estimatedMinutes != task.estimatedMinutes
            || importance != task.importance
    }

    private var trimmedNextAction: String {
        nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Intents

    func save() async {
        guard canSave else { return }

        var edited = task
        edited.title = trimmedTitle
        edited.notes = notes
        edited.nextAction = trimmedNextAction.isEmpty ? nil : trimmedNextAction
        edited.deadline = deadline
        edited.estimatedMinutes = estimatedMinutes
        edited.importance = importance
        edited.updatedAt = timeSource.now

        await persist(edited)
    }

    func complete() async {
        await apply { try self.task.completed(at: self.timeSource.now) }
    }

    func reopen() async {
        await apply { try self.task.reopened(at: self.timeSource.now) }
    }

    func archive() async {
        await apply { try self.task.archived(at: self.timeSource.now) }
    }

    /// Real deletion. There is no server copy and no tombstone (PRIVACY.md).
    func delete() async {
        do {
            try await repository.delete(id: task.id)
            isDeleted = true
            failure = nil
        } catch {
            failure = "NEXT could not delete that."
        }
    }

    private func apply(_ transition: () throws -> TaskItem) async {
        do {
            await persist(try transition())
        } catch {
            failure = "That change is not available for this task."
        }
    }

    private func persist(_ edited: TaskItem) async {
        do {
            try await repository.upsert(edited)
            task = edited
            syncEditsFromTask()
            failure = nil
        } catch {
            failure = "NEXT could not save that change."
        }
    }

    private func syncEditsFromTask() {
        title = task.title
        notes = task.notes
        nextAction = task.nextAction ?? ""
        deadline = task.deadline
        estimatedMinutes = task.estimatedMinutes
        importance = task.importance
    }
}
