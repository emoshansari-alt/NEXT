import Foundation
import Testing

@testable import NextKit

// MARK: - Deterministic dates
//
// Every test in this suite pins "now" to a fixed instant. NextKit is forbidden from reading
// the clock itself (DECISIONS.md D-007), so tests are fully reproducible and deadline edge
// cases can be expressed exactly.

/// Parses an ISO-8601 instant, e.g. `iso("2026-03-10T09:00:00Z")`.
/// Traps on a malformed literal — that is a mistake in the test, not a runtime condition.
func iso(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: string) else {
        fatalError("Malformed test date literal: \(string)")
    }
    return date
}

extension Date {
    /// The instant every test treats as "now": Tuesday 10 March 2026, 09:00 UTC.
    /// Mid-week and mid-morning, so that "tomorrow", "this weekend" and "overdue"
    /// are all expressible without wrapping past a month or year boundary.
    static let testReference = iso("2026-03-10T09:00:00Z")

    /// `Date.testReference` shifted by a whole number of hours. Negative means the past.
    static func hoursFromReference(_ hours: Double) -> Date {
        testReference.addingTimeInterval(hours * 3600)
    }

    /// `Date.testReference` shifted by a whole number of days. Negative means the past.
    static func daysFromReference(_ days: Double) -> Date {
        hoursFromReference(days * 24)
    }
}

// MARK: - Builders

/// Builds a `TaskItem` with sensible defaults so each test only states what it cares about.
func makeTask(
    id: String,
    title: String = "Untitled",
    status: TaskStatus = .active,
    deadline: Date? = nil,
    importance: Importance = .normal,
    estimatedMinutes: Int? = nil,
    nextAction: String? = nil,
    prerequisiteIDs: [TaskID] = [],
    parentID: TaskID? = nil,
    rejections: [Rejection] = [],
    rejectionsSupersededAt: Date? = nil,
    createdAt: Date = .testReference,
    updatedAt: Date? = nil,
    completedAt: Date? = nil
) -> TaskItem {
    TaskItem(
        id: TaskID(id),
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        status: status,
        completedAt: completedAt,
        deadline: deadline,
        importance: importance,
        estimatedMinutes: estimatedMinutes,
        nextAction: nextAction,
        prerequisiteIDs: prerequisiteIDs,
        parentID: parentID,
        rejections: rejections,
        rejectionsSupersededAt: rejectionsSupersededAt
    )
}

/// A rejection that happened a given number of hours before `Date.testReference`.
func rejection(_ reason: RejectionReason = .cantRightNow, hoursAgo: Double) -> Rejection {
    Rejection(reason: reason, at: .hoursFromReference(-hoursAgo))
}

// MARK: - The TaskRepository contract
//
// Storage is a seam (ARCHITECTURE.md §3, DECISIONS.md D-006), so the promises below are owed by
// every implementation of it — not just the in-memory one they happen to be exercised against
// at Tier 1. Written as a plain function rather than a suite so that NextApp's Tier 2 target can
// call the identical code against the SwiftData-backed store and have the same promises checked,
// instead of re-deriving them by hand and drifting.

/// Runs the whole `TaskRepository` contract against an implementation.
///
/// `make` must hand back a **fresh, empty** repository every time it is called. Each section
/// asks for its own, so no section can be perturbed by another's leftovers, and a store that
/// needs tearing down between sections gets the chance. Seeding goes through `upsert` because
/// initialisers are not part of the protocol — only these five methods are.
func verifyRepositoryContract(_ make: @Sendable () -> any TaskRepository) async throws {
    try await verifyReadingAndWriting(make())
    try await verifyStatusQueries(make())
    try await verifyOrdering(make())
    try await verifyConcurrency(make())
}

/// Insert, read back, replace, delete — and the two "absent is an ordinary answer" promises.
private func verifyReadingAndWriting(_ repository: any TaskRepository) async throws {
    let empty = try await repository.fetchAll()
    #expect(empty.isEmpty, "a fresh repository has nothing in it")

    let chem = makeTask(id: "chem", title: "Chemistry worksheet")
    try await repository.upsert(chem)
    #expect(try await repository.fetch(id: TaskID("chem")) == chem, "an upserted task reads back")

    // A missing task is an answer, not a failure: the widget, a notification action and the app
    // can all act on a snapshot that has since been deleted.
    #expect(
        try await repository.fetch(id: TaskID("never-existed")) == nil,
        "an unknown identifier returns nothing rather than throwing"
    )

    var edited = chem
    edited.title = "Chemistry worksheet, revised"
    edited.estimatedMinutes = 25
    try await repository.upsert(edited)

    let afterEdit = try await repository.fetchAll()
    #expect(afterEdit.count == 1, "upsert replaces by identity rather than duplicating")
    #expect(afterEdit.first?.title == "Chemistry worksheet, revised")
    #expect(afterEdit.first?.estimatedMinutes == 25)

    try await repository.upsert(makeTask(id: "essay", title: "History essay"))
    try await repository.delete(id: TaskID("chem"))
    #expect(
        try await repository.fetchAll().map(\.id) == [TaskID("essay")],
        "delete removes the named task and leaves the rest alone"
    )

    // Delete is reachable from more than one surface at once and from stale snapshots, so a
    // second one has to be harmless.
    try await repository.delete(id: TaskID("chem"))
    try await repository.delete(id: TaskID("essay"))
    #expect(try await repository.fetchAll().isEmpty, "deleting twice is a no-op, not an error")
}

/// The status queries the Everything screen's sections and the ranking engine's input are
/// built from.
private func verifyStatusQueries(_ repository: any TaskRepository) async throws {
    let mixed = [
        makeTask(id: "active-1", status: .active, createdAt: .hoursFromReference(1)),
        makeTask(id: "done", status: .completed, createdAt: .hoursFromReference(2)),
        makeTask(id: "active-2", status: .active, createdAt: .hoursFromReference(3)),
        makeTask(id: "filed", status: .archived, createdAt: .hoursFromReference(4))
    ]
    for task in mixed { try await repository.upsert(task) }

    #expect(
        try await repository.fetch(status: .active).map(\.id)
            == [TaskID("active-1"), TaskID("active-2")],
        "only tasks in the requested state come back, oldest first"
    )

    // Every state is queried, and nothing is lost or double-counted between them.
    var gathered: [TaskItem] = []
    for status in TaskStatus.allCases {
        let matches = try await repository.fetch(status: status)
        #expect(matches.allSatisfy { $0.status == status }, "a status query returns only that status")
        gathered.append(contentsOf: matches)
    }
    let all = try await repository.fetchAll()
    #expect(Set(gathered) == Set(all), "the status queries partition the whole repository")
    #expect(gathered.count == all.count, "the status queries do not double-count")

    for task in mixed { try await repository.delete(id: task.id) }
    try await repository.upsert(makeTask(id: "chem", status: .active))
    #expect(
        try await repository.fetch(status: .archived).isEmpty,
        "a state with nothing in it returns an empty list rather than an error"
    )

    try await repository.upsert(makeTask(id: "chem", status: .active).completed(at: .testReference))
    #expect(try await repository.fetch(status: .active).isEmpty, "a status change leaves the old query")
    #expect(try await repository.fetch(status: .completed).count == 1, "and joins the new one")
}

/// Ordering is part of the contract, not a convenience.
///
/// Ranking is a pure function of the list it is handed. A store that leaked its own iteration
/// order — hash order, say — would make the single recommendation on screen change between two
/// launches with identical data.
private func verifyOrdering(_ repository: any TaskRepository) async throws {
    let byAge = [
        makeTask(id: "newest", createdAt: .daysFromReference(2)),
        makeTask(id: "oldest", createdAt: .daysFromReference(-2)),
        makeTask(id: "middle", createdAt: .testReference)
    ]
    for task in byAge { try await repository.upsert(task) }

    #expect(
        try await repository.fetchAll().map(\.id)
            == [TaskID("oldest"), TaskID("middle"), TaskID("newest")],
        "results are oldest first, whatever order they went in"
    )

    for task in byAge { try await repository.delete(id: task.id) }

    // Tasks captured from one brain dump share a creation instant exactly, so the identifier
    // tie-break is what makes the order total rather than merely sorted.
    for id in ["c", "a", "b"] { try await repository.upsert(makeTask(id: id)) }
    #expect(
        try await repository.fetchAll().map(\.id.rawValue) == ["a", "b", "c"],
        "tasks created at the same instant are ordered by identifier"
    )

    let first = try await repository.fetchAll()
    let second = try await repository.fetchAll()
    #expect(first == second, "repeated reads of an unchanged repository are identical")
}

/// Callers reach the store from several tasks at once — a view model refreshing while a
/// notification action completes something — so writes must not be lost or duplicated.
private func verifyConcurrency(_ repository: any TaskRepository) async throws {
    await withTaskGroup(of: Void.self) { group in
        for index in 0..<100 {
            group.addTask {
                _ = try? await repository.upsert(
                    makeTask(id: "t\(index)", createdAt: .hoursFromReference(Double(index)))
                )
            }
            group.addTask {
                _ = try? await repository.fetchAll()
            }
        }
    }

    let all = try await repository.fetchAll()
    #expect(all.count == 100, "every concurrent write is recorded")
    #expect(Set(all.map(\.id)).count == 100, "and none is duplicated")
    #expect(all == (try await repository.fetchAll()), "the settled result is stable")
}
