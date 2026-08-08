import Foundation
import Testing

@testable import NextKit

// The storage seam from ARCHITECTURE.md §3 and D-006. These tests pin the *contract* — the
// SwiftData-backed implementation in NextApp has to honour exactly the same one, so anything
// asserted here is a promise about both implementations, not a quirk of the in-memory one.

@Suite("TaskRepository — reading and writing")
struct TaskRepositoryReadWriteTests {

    @Test("an empty repository has nothing in it")
    func emptyRepositoryIsEmpty() async throws {
        let repository = InMemoryTaskRepository()

        let all = try await repository.fetchAll()

        #expect(all.isEmpty)
    }

    @Test("a seeded repository returns what it was given")
    func seededRepositoryReturnsSeed() async throws {
        let repository = InMemoryTaskRepository([
            makeTask(id: "chem", title: "Chemistry worksheet"),
            makeTask(id: "essay", title: "History essay")
        ])

        let all = try await repository.fetchAll()

        #expect(all.count == 2)
    }

    @Test("an upserted task can be fetched back by identifier")
    func upsertThenFetchByID() async throws {
        let repository = InMemoryTaskRepository()
        let chem = makeTask(id: "chem", title: "Chemistry worksheet")

        try await repository.upsert(chem)
        let found = try await repository.fetch(id: TaskID("chem"))

        #expect(found == chem)
    }

    @Test("fetching an identifier that was never stored returns nothing, and does not throw")
    func fetchingUnknownIDReturnsNil() async throws {
        let repository = InMemoryTaskRepository([makeTask(id: "chem")])

        let found = try await repository.fetch(id: TaskID("never-existed"))

        #expect(found == nil)
    }

    @Test("upserting the same identifier updates in place rather than duplicating")
    func upsertReplacesByIdentity() async throws {
        let repository = InMemoryTaskRepository()
        let original = makeTask(id: "chem", title: "Chemistry")
        var edited = original
        edited.title = "Chemistry worksheet"
        edited.estimatedMinutes = 25

        try await repository.upsert(original)
        try await repository.upsert(edited)

        let all = try await repository.fetchAll()
        #expect(all.count == 1)
        #expect(all.first?.title == "Chemistry worksheet")
        #expect(all.first?.estimatedMinutes == 25)
    }

    @Test("deleting removes the task and leaves the rest alone")
    func deleteRemovesOnlyTheNamedTask() async throws {
        let repository = InMemoryTaskRepository([
            makeTask(id: "chem"), makeTask(id: "essay")
        ])

        try await repository.delete(id: TaskID("chem"))

        let remaining = try await repository.fetchAll().map(\.id)
        #expect(remaining == [TaskID("essay")])
    }

    @Test("deleting something that is not there is a no-op, not an error")
    func deletingUnknownIDIsIdempotent() async throws {
        // The user can reach delete from two surfaces at once, and the widget can act on a
        // stale snapshot. A second delete must be harmless.
        let repository = InMemoryTaskRepository([makeTask(id: "chem")])

        try await repository.delete(id: TaskID("chem"))
        try await repository.delete(id: TaskID("chem"))

        let all = try await repository.fetchAll()
        #expect(all.isEmpty)
    }
}

@Suite("TaskRepository — fetching by status")
struct TaskRepositoryStatusTests {

    private var mixed: [TaskItem] {
        [
            makeTask(id: "active-1", status: .active, createdAt: .hoursFromReference(1)),
            makeTask(id: "done", status: .completed, createdAt: .hoursFromReference(2)),
            makeTask(id: "active-2", status: .active, createdAt: .hoursFromReference(3)),
            makeTask(id: "filed", status: .archived, createdAt: .hoursFromReference(4))
        ]
    }

    @Test("only tasks in the requested state come back, oldest first")
    func statusFilterSelects() async throws {
        let repository = InMemoryTaskRepository(mixed)

        let active = try await repository.fetch(status: .active).map(\.id)

        #expect(active == [TaskID("active-1"), TaskID("active-2")])
    }

    @Test("a state with nothing in it returns an empty list rather than an error")
    func emptyStatusIsEmptyList() async throws {
        let repository = InMemoryTaskRepository([makeTask(id: "chem", status: .active)])

        let archived = try await repository.fetch(status: .archived)

        #expect(archived.isEmpty)
    }

    @Test("the status queries partition the whole repository, losing nothing")
    func statusQueriesPartitionEverything() async throws {
        let repository = InMemoryTaskRepository(mixed)
        var gathered: [TaskItem] = []

        for status in TaskStatus.allCases {
            let matches = try await repository.fetch(status: status)
            #expect(matches.allSatisfy { $0.status == status })
            gathered.append(contentsOf: matches)
        }

        let all = try await repository.fetchAll()
        #expect(Set(gathered) == Set(all))
        #expect(gathered.count == all.count)
    }

    @Test("changing a task's status moves it between the two queries")
    func statusChangeIsReflected() async throws {
        let repository = InMemoryTaskRepository()
        let chem = makeTask(id: "chem", status: .active)
        try await repository.upsert(chem)

        try await repository.upsert(chem.completed(at: .testReference))

        let active = try await repository.fetch(status: .active)
        let completed = try await repository.fetch(status: .completed)
        #expect(active.isEmpty)
        #expect(completed.count == 1)
    }
}

@Suite("TaskRepository — determinism")
struct TaskRepositoryDeterminismTests {

    @Test("results are ordered oldest first, whatever order they went in")
    func resultsAreOrderedByCreation() async throws {
        let repository = InMemoryTaskRepository([
            makeTask(id: "newest", createdAt: .daysFromReference(2)),
            makeTask(id: "oldest", createdAt: .daysFromReference(-2)),
            makeTask(id: "middle", createdAt: .testReference)
        ])

        let order = try await repository.fetchAll().map(\.id)

        #expect(order == [TaskID("oldest"), TaskID("middle"), TaskID("newest")])
    }

    @Test("tasks created at the same instant are ordered by identifier")
    func identicalCreationBreaksTieByIdentifier() async throws {
        let repository = InMemoryTaskRepository([
            makeTask(id: "c"), makeTask(id: "a"), makeTask(id: "b")
        ])

        let order = try await repository.fetchAll().map(\.id.rawValue)

        #expect(order == ["a", "b", "c"])
    }

    @Test("insertion order cannot leak into results")
    func insertionOrderDoesNotLeak() async throws {
        // A dictionary-backed store hashes its keys, so iterating it directly would produce an
        // order that varies from run to run. Ranking is a pure function of the list it is
        // handed, so an unstable list would make the whole engine unstable.
        let tasks = (0..<40).map {
            makeTask(id: "t\($0)", createdAt: .hoursFromReference(Double($0)))
        }
        let forwards = InMemoryTaskRepository(tasks)
        let backwards = InMemoryTaskRepository(tasks.reversed())

        let fromForwards = try await forwards.fetchAll()
        let fromBackwards = try await backwards.fetchAll()

        #expect(fromForwards == fromBackwards)
        #expect(fromForwards.map(\.id) == tasks.map(\.id))
    }

    @Test("repeated reads of an unchanged repository are identical")
    func repeatedReadsAgree() async throws {
        let repository = InMemoryTaskRepository((0..<40).map { makeTask(id: "t\($0)") })

        let first = try await repository.fetchAll()
        let second = try await repository.fetchAll()

        #expect(first == second)
    }
}

@Suite("TaskRepository — concurrency")
struct TaskRepositoryConcurrencyTests {

    @Test("concurrent writes are all recorded")
    func concurrentUpsertsAllLand() async throws {
        let repository = InMemoryTaskRepository()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    _ = try? await repository.upsert(
                        makeTask(id: "t\(index)", createdAt: .hoursFromReference(Double(index)))
                    )
                }
            }
        }

        let all = try await repository.fetchAll()
        #expect(all.count == 200)
    }

    @Test("concurrent writes and reads do not lose or duplicate work")
    func concurrentReadWriteMixIsConsistent() async throws {
        let repository = InMemoryTaskRepository()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    _ = try? await repository.upsert(makeTask(id: "t\(index)"))
                }
                group.addTask {
                    _ = try? await repository.fetchAll()
                }
            }
        }

        let all = try await repository.fetchAll()
        #expect(all.count == 100)
        #expect(Set(all.map(\.id)).count == 100)
    }
}

@Suite("TaskRepository — as an abstraction")
struct TaskRepositoryAbstractionTests {

    /// Every caller in `NextApp` holds the protocol, never the concrete type. That this
    /// compiles and passes is what makes the SwiftData implementation a drop-in.
    private func firstActiveTitle(in repository: any TaskRepository) async throws -> String? {
        try await repository.fetch(status: .active).first?.title
    }

    @Test("callers can work against the protocol alone")
    func usableThroughTheProtocol() async throws {
        let repository: any TaskRepository = InMemoryTaskRepository([
            makeTask(id: "done", title: "Old thing", status: .completed),
            makeTask(id: "chem", title: "Chemistry worksheet", status: .active)
        ])

        let title = try await firstActiveTitle(in: repository)

        #expect(title == "Chemistry worksheet")
    }

    @Test("the ranking engine can be fed straight from the repository")
    func feedsTheRankingEngine() async throws {
        // The whole point of the seam: storage hands plain value types to a pure function.
        let repository = InMemoryTaskRepository([
            makeTask(id: "later", title: "Reading", deadline: .daysFromReference(6)),
            makeTask(id: "soon", title: "Chemistry worksheet", deadline: .hoursFromReference(4))
        ])

        let stored = try await repository.fetchAll()
        let outcome = RankingEngine().recommend(
            from: stored, context: RankingContext(now: .testReference)
        )

        #expect(try #require(outcome.recommendation).task.id == TaskID("soon"))
    }
}
