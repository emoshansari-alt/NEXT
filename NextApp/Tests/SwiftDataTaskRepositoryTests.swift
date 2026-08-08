import Foundation
import SwiftData
import Testing

@testable import NextApp
import NextKit
import NextKitTestSupport

/// Tier 2. The real store, held to exactly the promises the in-memory one is held to at Tier 1.
///
/// `verifyRepositoryContract` is the same function `NextKitTests` runs — imported from
/// `NextKitTestSupport`, not copied. That is the whole point: a storage contract that only the
/// in-memory implementation can execute describes one implementation rather than binding both.
/// If SwiftData orders differently, loses a concurrent write, or throws where the contract says
/// it must return nothing, this fails.
@Suite("SwiftDataTaskRepository — the storage contract")
struct SwiftDataTaskRepositoryTests {

    @Test("SwiftData honours the TaskRepository contract")
    func swiftDataHonoursTheContract() async throws {
        try await verifyRepositoryContract {
            // A fresh in-memory container per section, as the contract requires. In-memory so
            // the suite leaves nothing on the simulator's disk between runs.
            let container = try ModelContainer(
                for: StoredTask.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            return SwiftDataTaskRepository(modelContainer: container)
        }
    }
}

@Suite("StoredTask — mapping")
struct StoredTaskMappingTests {

    private let reference = contractReference

    private func roundTrip(_ task: TaskItem) -> TaskItem {
        StoredTask(task: task).domainValue
    }

    @Test("every field survives a round trip through storage")
    func allFieldsRoundTrip() {
        // Named field by field rather than compared whole, so that a field added to TaskItem
        // and forgotten in the mapping shows up as a specific failure. The whole-value check
        // below is what actually catches an omission.
        let task = TaskItem(
            id: TaskID("chem"),
            title: "Chemistry worksheet",
            createdAt: reference,
            updatedAt: contractHours(2),
            status: .completed,
            completedAt: contractHours(3),
            deadline: contractHours(24),
            importance: .important,
            estimatedMinutes: 25,
            nextAction: "Do questions 1 to 5.",
            prerequisiteIDs: [TaskID("reading"), TaskID("lab")],
            parentID: TaskID("coursework"),
            rejections: [
                Rejection(reason: .cantRightNow, at: contractHours(-4)),
                Rejection(reason: .needLessEffort, at: contractHours(-1))
            ],
            rejectionsSupersededAt: contractHours(-2)
        )

        #expect(roundTrip(task) == task)
    }

    @Test("a task with nothing optional filled in round trips too")
    func sparseTaskRoundTrips() {
        let bare = TaskItem(id: TaskID("bare"), title: "Something", createdAt: reference)

        #expect(roundTrip(bare) == bare)
    }

    @Test("sub-second instants are preserved exactly")
    func subSecondPrecisionSurvives() {
        // Rejections are JSON-encoded. An ISO-8601 strategy would silently truncate here, and a
        // task would stop comparing equal to itself after a save.
        let precise = reference.addingTimeInterval(0.123_456)
        let task = TaskItem(
            id: TaskID("t"),
            title: "T",
            createdAt: reference,
            rejections: [Rejection(reason: .other, at: precise)]
        )

        #expect(roundTrip(task).rejections.first?.at == precise)
    }

    @Test("an unreadable rejection blob costs the metadata, never the task")
    func corruptRejectionsDoNotLoseTheTask() {
        // Lenience here is deliberate and one-directional. Tuning data the app cannot parse is
        // not worth losing the thing the student actually wrote down.
        let row = StoredTask(task: TaskItem(id: TaskID("t"), title: "History essay", createdAt: reference))
        row.rejectionsData = Data("not json".utf8)

        let recovered = row.domainValue

        #expect(recovered.title == "History essay")
        #expect(recovered.rejections.isEmpty)
    }

    @Test("an unrecognised status is treated as outstanding, not dropped")
    func unknownStatusFallsBackToActive() {
        // A status written by a future version must not make a task vanish from every screen.
        let row = StoredTask(task: TaskItem(id: TaskID("t"), title: "History essay", createdAt: reference))
        row.statusRaw = "snoozed-in-some-later-version"

        #expect(row.domainValue.status == .active)
    }
}
