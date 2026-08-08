import Foundation
import Testing

@testable import NextKit

// The storage seam from ARCHITECTURE.md §3 and D-006.
//
// The promises owed by *every* implementation live in `verifyRepositoryContract(_:)` in the test
// support file, not here, because they are facts about the seam rather than about one class —
// the SwiftData-backed store in NextApp owes the caller exactly the same behaviour and its Tier 2
// target can run the identical function. What remains in this file is what is genuinely specific
// to `InMemoryTaskRepository`: its seeding initialiser, which is not part of the protocol, and
// the way it is wired to the rest of the domain.

@Suite("TaskRepository — the shared contract")
struct TaskRepositoryContractTests {

    @Test("the in-memory implementation honours the repository contract")
    func inMemoryHonoursTheContract() async throws {
        try await verifyRepositoryContract { InMemoryTaskRepository() }
    }
}

@Suite("InMemoryTaskRepository — seeding")
struct InMemoryTaskRepositorySeedingTests {

    @Test("a seeded repository returns what it was given")
    func seededRepositoryReturnsSeed() async throws {
        let repository = InMemoryTaskRepository([
            makeTask(id: "chem", title: "Chemistry worksheet"),
            makeTask(id: "essay", title: "History essay")
        ])

        let all = try await repository.fetchAll()

        #expect(all.count == 2)
    }

    @Test("a later duplicate in the seed wins, matching upsert")
    func seedingFollowsUpsertSemantics() async throws {
        var revised = makeTask(id: "chem", title: "Chemistry")
        revised.title = "Chemistry worksheet"

        let repository = InMemoryTaskRepository([makeTask(id: "chem", title: "Chemistry"), revised])

        let all = try await repository.fetchAll()
        #expect(all.count == 1)
        #expect(all.first?.title == "Chemistry worksheet")
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
