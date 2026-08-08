import Foundation
import Testing

@testable import NextApp
import NextKit

private struct FixedTimeSource: TimeSource {
    let now: Date
}

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let reference = Date(timeIntervalSince1970: 1_773_133_200)  // 2026-03-10 09:00 UTC

private func task(
    _ id: String,
    title: String? = nil,
    status: TaskStatus = .active,
    deadlineHours: Double? = nil
) -> TaskItem {
    TaskItem(
        id: TaskID(id),
        title: title ?? id,
        createdAt: reference,
        status: status,
        deadline: deadlineHours.map { reference.addingTimeInterval($0 * 3600) }
    )
}

@MainActor
@Suite("EverythingViewModel")
struct EverythingViewModelTests {

    private func loaded(_ tasks: [TaskItem]) async throws -> (EverythingViewModel, InMemoryTaskRepository) {
        let repository = InMemoryTaskRepository()
        for task in tasks { try await repository.upsert(task) }

        let model = EverythingViewModel(
            repository: repository,
            timeSource: FixedTimeSource(now: reference),
            calendar: utc
        )
        await model.load()
        return (model, repository)
    }

    @Test("tasks land in the section their deadline puts them in")
    func tasksAreSectioned() async throws {
        let (model, _) = try await loaded([
            task("late", deadlineHours: -30),
            task("soon", deadlineHours: 5),
            task("later", deadlineHours: 96),
            task("someday"),
            task("finished", status: .completed)
        ])

        #expect(model.sections.overdue.map(\.id.rawValue) == ["late"])
        #expect(model.sections.today.map(\.id.rawValue) == ["soon"])
        #expect(model.sections.upcoming.map(\.id.rawValue) == ["later"])
        #expect(model.sections.undated.map(\.id.rawValue) == ["someday"])
        #expect(model.sections.completed.map(\.id.rawValue) == ["finished"])
    }

    @Test("completing from Everything writes through and moves the task")
    func completingMovesTheTask() async throws {
        let (model, repository) = try await loaded([task("chem", deadlineHours: 5)])

        await model.complete(task("chem", deadlineHours: 5))

        #expect(model.sections.today.isEmpty)
        #expect(model.sections.completed.map(\.id.rawValue) == ["chem"])
        #expect(try await repository.fetch(id: TaskID("chem"))?.status == .completed)
    }

    @Test("deleting really removes it, with no tombstone left behind")
    func deletingRemoves() async throws {
        let (model, repository) = try await loaded([task("chem")])

        await model.delete(task("chem"))

        #expect(model.sections.isEmpty)
        #expect(try await repository.fetchAll().isEmpty)
    }

    @Test("reopening finished work puts it back in the outstanding sections")
    func reopeningRestores() async throws {
        let done = try task("chem").completed(at: reference)
        let (model, _) = try await loaded([done])

        await model.reopen(done)

        #expect(model.sections.completed.isEmpty)
        #expect(model.sections.undated.map(\.id.rawValue) == ["chem"])
    }

    @Test("a refused change is reported rather than silently ignored")
    func refusedChangeIsSurfaced() async throws {
        // Completing something already completed is reachable from a stale tap. It must not
        // look like it worked.
        let done = try task("chem").completed(at: reference)
        let (model, _) = try await loaded([done])

        await model.complete(done)

        #expect(model.storeFailure != nil)
    }
}

@MainActor
@Suite("TaskDetailViewModel")
struct TaskDetailViewModelTests {

    private func detail(
        _ item: TaskItem
    ) async throws -> (TaskDetailViewModel, InMemoryTaskRepository) {
        let repository = InMemoryTaskRepository()
        try await repository.upsert(item)
        let model = TaskDetailViewModel(
            task: item,
            repository: repository,
            timeSource: FixedTimeSource(now: reference)
        )
        return (model, repository)
    }

    @Test("edits are held locally until saved")
    func editsAreNotWrittenUntilSave() async throws {
        // Backing out of a half-typed title must not be what gets stored.
        let (model, repository) = try await detail(task("chem", title: "Chem"))

        model.title = "Chemistry worksheet"

        #expect(try await repository.fetch(id: TaskID("chem"))?.title == "Chem")
        #expect(model.hasChanges)
    }

    @Test("saving writes every edited field")
    func saveWritesEverything() async throws {
        let (model, repository) = try await detail(task("chem", title: "Chem"))
        let due = reference.addingTimeInterval(48 * 3600)

        model.title = "  Chemistry worksheet  "
        model.notes = "Questions 1 to 5, from the green book."
        model.nextAction = "  Open the green book.  "
        model.deadline = due
        model.estimatedMinutes = 25
        model.importance = .important
        await model.save()

        let stored = try #require(try await repository.fetch(id: TaskID("chem")))
        #expect(stored.title == "Chemistry worksheet", "whitespace is trimmed")
        #expect(stored.notes == "Questions 1 to 5, from the green book.")
        #expect(stored.nextAction == "Open the green book.")
        #expect(stored.deadline == due)
        #expect(stored.estimatedMinutes == 25)
        #expect(stored.importance == .important)
        #expect(stored.updatedAt == reference)
    }

    @Test("a task cannot be saved with no name")
    func blankTitleCannotBeSaved() async throws {
        // A task with no name is not a task — it is a row nobody can identify later.
        let (model, repository) = try await detail(task("chem", title: "Chem"))

        model.title = "   "

        #expect(model.canSave == false)
        await model.save()
        #expect(try await repository.fetch(id: TaskID("chem"))?.title == "Chem")
    }

    @Test("saving with nothing changed is not offered")
    func noChangesMeansNothingToSave() async throws {
        let (model, _) = try await detail(task("chem"))

        #expect(model.hasChanges == false)
        #expect(model.canSave == false)
    }

    @Test("clearing the next action removes it rather than storing whitespace")
    func clearingNextActionStoresNil() async throws {
        var item = task("chem")
        item.nextAction = "Open the book."
        let (model, repository) = try await detail(item)

        model.nextAction = "   "
        await model.save()

        #expect(try await repository.fetch(id: TaskID("chem"))?.nextAction == nil)
    }

    @Test("deleting marks the screen finished so it can close itself")
    func deletingFlagsCompletion() async throws {
        let (model, repository) = try await detail(task("chem"))

        await model.delete()

        #expect(model.isDeleted)
        #expect(try await repository.fetchAll().isEmpty)
    }

    @Test("completing from detail records the instant")
    func completingRecordsTheInstant() async throws {
        let (model, repository) = try await detail(task("chem"))

        await model.complete()

        let stored = try #require(try await repository.fetch(id: TaskID("chem")))
        #expect(stored.status == .completed)
        #expect(stored.completedAt == reference)
        #expect(model.task.status == .completed, "the screen reflects the write")
    }
}
