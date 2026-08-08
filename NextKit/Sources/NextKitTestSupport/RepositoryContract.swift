import Foundation
import NextKit

/// The `TaskRepository` contract, as an executable specification.
///
/// This lives in a **library** target rather than in `NextKitTests` for one reason: the promises
/// below are owed by *every* implementation of the seam, and the implementation that matters
/// most — the SwiftData-backed store in `NextApp` — cannot be compiled on the Windows
/// development machine at all. A contract that only the in-memory implementation can run is not
/// a contract, it is a description of one implementation.
///
/// `NextKitTests` runs it at Tier 1 against `InMemoryTaskRepository`; `NextAppTests` runs the
/// identical function at Tier 2 against SwiftData. Neither re-derives the rules by hand, so
/// they cannot drift apart.
///
/// ## Why it throws instead of using `#expect`
///
/// `Testing` is a test-target facility. Importing it here would make this target
/// untouchable by anything that is not itself a test bundle, which defeats the purpose.
/// Throwing on the first violation keeps the function pure Swift and callable from anywhere —
/// a test target simply lets the error propagate and the framework reports it.

/// A promise the store did not keep.
public struct RepositoryContractViolation: Error, CustomStringConvertible {

    /// The rule that was broken, in the words of the contract.
    public let requirement: String

    /// What actually happened.
    public let detail: String

    public var description: String {
        "TaskRepository contract violated — \(requirement). \(detail)"
    }
}

// `detail` is an ordinary parameter rather than an `@autoclosure`: describing a failure here
// almost always means showing what the store actually returned, and reading a store is `async
// throws`. An autoclosure cannot carry either effect, and precomputing the value has the
// happy side effect of stopping the checks from querying twice.
private func require(
    _ condition: Bool,
    _ requirement: String,
    _ detail: String = ""
) throws {
    guard !condition else { return }
    throw RepositoryContractViolation(requirement: requirement, detail: detail)
}

// MARK: - Fixtures

/// The instant the contract treats as "now": Tuesday 10 March 2026, 09:00 UTC.
public let contractReference: Date = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: "2026-03-10T09:00:00Z") else {
        preconditionFailure("the contract's reference instant is malformed")
    }
    return date
}()

/// `contractReference` shifted by whole hours. Negative means the past.
public func contractHours(_ hours: Double) -> Date {
    contractReference.addingTimeInterval(hours * 3600)
}

/// A minimal task for contract exercises. Only the fields the contract actually reasons about.
public func contractTask(
    id: String,
    title: String = "Untitled",
    status: TaskStatus = .active,
    createdAt: Date = contractReference,
    estimatedMinutes: Int? = nil
) -> TaskItem {
    TaskItem(
        id: TaskID(id),
        title: title,
        createdAt: createdAt,
        status: status,
        estimatedMinutes: estimatedMinutes
    )
}

// MARK: - The contract

/// Runs every promise `TaskRepository` makes against one implementation.
///
/// `make` must hand back a **fresh, empty** repository each time it is called. Every section
/// asks for its own, so no section can be perturbed by another's leftovers, and a store that
/// needs tearing down between sections gets the chance. Seeding goes through `upsert` because
/// initialisers are not part of the protocol — only the five methods are.
public func verifyRepositoryContract(
    _ make: @Sendable () async throws -> any TaskRepository
) async throws {
    try await verifyReadingAndWriting(make())
    try await verifyStatusQueries(make())
    try await verifyOrdering(make())
    try await verifyConcurrency(make())
}

/// Insert, read back, replace, delete — and the two "absent is an ordinary answer" promises.
private func verifyReadingAndWriting(_ repository: any TaskRepository) async throws {
    let initial = try await repository.fetchAll()
    try require(
        initial.isEmpty,
        "a fresh repository is empty",
        "found \(initial.count) task(s)"
    )

    let chem = contractTask(id: "chem", title: "Chemistry worksheet")
    try await repository.upsert(chem)
    let readBack = try await repository.fetch(id: TaskID("chem"))
    try require(
        readBack == chem,
        "an upserted task reads back unchanged",
        "got \(String(describing: readBack))"
    )

    // A missing task is an answer, not a failure: the widget, a notification action and the app
    // can all act on a snapshot that has since been deleted.
    let missing = try await repository.fetch(id: TaskID("never-existed"))
    try require(
        missing == nil,
        "an unknown identifier returns nil rather than throwing",
        "got \(String(describing: missing))"
    )

    var edited = chem
    edited.title = "Chemistry worksheet, revised"
    edited.estimatedMinutes = 25
    try await repository.upsert(edited)

    let afterEdit = try await repository.fetchAll()
    try require(
        afterEdit.count == 1,
        "upsert replaces by identity rather than duplicating",
        "store holds \(afterEdit.count) task(s)"
    )
    try require(
        afterEdit.first == edited,
        "the replacement is the task that was written",
        "got \(String(describing: afterEdit.first))"
    )

    try await repository.upsert(contractTask(id: "essay", title: "History essay"))
    try await repository.delete(id: TaskID("chem"))
    let afterDelete = try await repository.fetchAll()
    try require(
        afterDelete.map(\.id) == [TaskID("essay")],
        "delete removes the named task and leaves the rest alone",
        "remaining: \(afterDelete.map(\.id.rawValue))"
    )

    // Delete is reachable from more than one surface at once and from stale snapshots, so a
    // second one has to be harmless.
    try await repository.delete(id: TaskID("chem"))
    try await repository.delete(id: TaskID("essay"))
    let emptied = try await repository.fetchAll()
    try require(
        emptied.isEmpty,
        "deleting twice is a no-op rather than an error",
        "remaining: \(emptied.map(\.id.rawValue))"
    )
}

/// The status queries the Everything screen's sections and the ranking engine's input are
/// built from.
private func verifyStatusQueries(_ repository: any TaskRepository) async throws {
    let mixed = [
        contractTask(id: "active-1", status: .active, createdAt: contractHours(1)),
        contractTask(id: "done", status: .completed, createdAt: contractHours(2)),
        contractTask(id: "active-2", status: .active, createdAt: contractHours(3)),
        contractTask(id: "filed", status: .archived, createdAt: contractHours(4))
    ]
    for task in mixed { try await repository.upsert(task) }

    let actives = try await repository.fetch(status: .active)
    try require(
        actives.map(\.id) == [TaskID("active-1"), TaskID("active-2")],
        "a status query returns only that status, oldest first",
        "got \(actives.map(\.id.rawValue))"
    )

    var gathered: [TaskItem] = []
    for status in TaskStatus.allCases {
        let matches = try await repository.fetch(status: status)
        try require(
            matches.allSatisfy { $0.status == status },
            "a status query never returns another status",
            "querying \(status) returned \(matches.map(\.status))"
        )
        gathered.append(contentsOf: matches)
    }

    let all = try await repository.fetchAll()
    try require(
        Set(gathered) == Set(all),
        "the status queries partition the whole store",
        "\(gathered.count) gathered vs \(all.count) total"
    )
    try require(
        gathered.count == all.count,
        "the status queries do not double-count",
        "\(gathered.count) gathered vs \(all.count) total"
    )

    for task in mixed { try await repository.delete(id: task.id) }
    try await repository.upsert(contractTask(id: "chem", status: .active))
    let noneArchived = try await repository.fetch(status: .archived)
    try require(
        noneArchived.isEmpty,
        "a state with nothing in it returns an empty list rather than an error",
        "got \(noneArchived.map(\.id.rawValue))"
    )

    try await repository.upsert(
        try contractTask(id: "chem", status: .active).completed(at: contractReference)
    )
    let stillActive = try await repository.fetch(status: .active)
    let nowComplete = try await repository.fetch(status: .completed)
    try require(
        stillActive.isEmpty,
        "a status change leaves the old query",
        "still active: \(stillActive.map(\.id.rawValue))"
    )
    try require(
        nowComplete.count == 1,
        "and joins the new one",
        "completed: \(nowComplete.map(\.id.rawValue))"
    )
}

/// Ordering is part of the contract, not a convenience.
///
/// Ranking is a pure function of the list it is handed. A store that leaked its own iteration
/// order — hash order, say — would make the single recommendation on screen change between two
/// launches with identical data.
private func verifyOrdering(_ repository: any TaskRepository) async throws {
    let byAge = [
        contractTask(id: "newest", createdAt: contractHours(48)),
        contractTask(id: "oldest", createdAt: contractHours(-48)),
        contractTask(id: "middle", createdAt: contractReference)
    ]
    for task in byAge { try await repository.upsert(task) }

    let byAgeResult = try await repository.fetchAll()
    try require(
        byAgeResult.map(\.id) == [TaskID("oldest"), TaskID("middle"), TaskID("newest")],
        "results are oldest first, whatever order they went in",
        "got \(byAgeResult.map(\.id.rawValue))"
    )

    for task in byAge { try await repository.delete(id: task.id) }

    // Tasks captured from one brain dump share a creation instant exactly, so the identifier
    // tie-break is what makes the order total rather than merely sorted.
    for id in ["c", "a", "b"] { try await repository.upsert(contractTask(id: id)) }
    let tied = try await repository.fetchAll()
    try require(
        tied.map(\.id.rawValue) == ["a", "b", "c"],
        "tasks created at the same instant are ordered by identifier",
        "got \(tied.map(\.id.rawValue))"
    )

    let first = try await repository.fetchAll()
    let second = try await repository.fetchAll()
    try require(
        first == second,
        "repeated reads of an unchanged store are identical"
    )
}

/// Callers reach the store from several tasks at once — a view model refreshing while a
/// notification action completes something — so writes must not be lost or duplicated.
private func verifyConcurrency(_ repository: any TaskRepository) async throws {
    await withTaskGroup(of: Void.self) { group in
        for index in 0..<100 {
            group.addTask {
                try? await repository.upsert(
                    contractTask(id: "t\(index)", createdAt: contractHours(Double(index)))
                )
            }
            group.addTask {
                _ = try? await repository.fetchAll()
            }
        }
    }

    let all = try await repository.fetchAll()
    let again = try await repository.fetchAll()
    try require(all.count == 100, "every concurrent write is recorded", "found \(all.count)")
    try require(
        Set(all.map(\.id)).count == 100,
        "and none is duplicated",
        "\(Set(all.map(\.id)).count) distinct identifiers"
    )
    try require(
        all == again,
        "the settled result is stable",
        "two consecutive reads differed"
    )
}
