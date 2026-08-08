import Foundation
import Testing

@testable import NextApp
import NextKit

// Tier 2 unit tests. These run on the iOS Simulator and cover the app layer's own logic — the
// wiring between the store, the engine and the screen. Engine behaviour itself is covered at
// Tier 1 in NextKit and is not re-tested here.
//
// The view model is driven through a real `InMemoryTaskRepository` rather than a stub, so these
// exercise the same seam the SwiftData store implements.

/// A clock pinned to one instant, so deadline behaviour can be asserted exactly.
private struct FixedTimeSource: TimeSource {
    let now: Date
}

@MainActor
@Suite("TodayViewModel")
struct TodayViewModelTests {

    private let now = Date(timeIntervalSince1970: 1_773_133_200)  // 2026-03-10 09:00 UTC

    private func task(
        _ id: String,
        deadlineHours: Double? = nil,
        nextAction: String? = nil
    ) -> TaskItem {
        TaskItem(
            id: TaskID(id),
            title: id,
            createdAt: now,
            deadline: deadlineHours.map { now.addingTimeInterval($0 * 3600) },
            nextAction: nextAction
        )
    }

    /// A loaded view model over a store seeded with exactly these tasks.
    ///
    /// Seeding before `load()` matters: an empty store makes the view model plant sample tasks,
    /// which is correct behaviour today but would silently replace the fixture.
    private func loaded(_ tasks: [TaskItem]) async throws -> TodayViewModel {
        let repository = InMemoryTaskRepository()
        for task in tasks { try await repository.upsert(task) }

        let model = TodayViewModel(repository: repository, timeSource: FixedTimeSource(now: now))
        await model.load()
        return model
    }

    @Test("recommends the most urgent task on launch")
    func recommendsOnLaunch() async throws {
        let model = try await loaded([task("later", deadlineHours: 72), task("sooner", deadlineHours: 4)])

        #expect(try #require(model.recommendation).task.id == TaskID("sooner"))
    }

    @Test("a first run shows the empty state and invents nothing")
    func emptyStoreStaysEmpty() async throws {
        // This replaces the seeding tripwire from Phase 2. Sample tasks existed only because
        // capture did not; now that it does, a store the user has not written to must stay
        // untouched. An app that plants tasks a student never wrote is lying to them.
        let repository = InMemoryTaskRepository()
        let model = TodayViewModel(repository: repository, timeSource: FixedTimeSource(now: now))

        await model.load()

        #expect(model.outcome == .nothingToDo)
        #expect(try await repository.fetchAll().isEmpty)
    }

    @Test("START opens Focus on the recommended task")
    func startOpensFocus() async throws {
        let model = try await loaded([task("only", deadlineHours: 4)])

        await model.startRecommended()

        #expect(try #require(model.focused).id == TaskID("only"))
    }

    @Test("starting a task is written to the store, not held only on screen")
    func startingPersists() async throws {
        let repository = InMemoryTaskRepository()
        try await repository.upsert(task("only", deadlineHours: 4))
        let model = TodayViewModel(repository: repository, timeSource: FixedTimeSource(now: now))
        await model.load()

        await model.startRecommended()

        let stored = try #require(try await repository.fetch(id: TaskID("only")))
        #expect(stored.updatedAt == now)
        #expect(stored.rejectionsSupersededAt == now)
    }

    @Test("completing the focused task closes Focus and recommends the next thing")
    func completingAdvancesTheLoop() async throws {
        // The core loop: START, DONE, NEXT.
        let model = try await loaded([task("first", deadlineHours: 2), task("second", deadlineHours: 6)])
        await model.startRecommended()

        await model.completeFocused()

        #expect(model.focused == nil)
        #expect(try #require(model.recommendation).task.id == TaskID("second"))
    }

    @Test("completion survives in the store, not just in the view")
    func completionPersists() async throws {
        let repository = InMemoryTaskRepository()
        try await repository.upsert(task("only", deadlineHours: 2))
        let model = TodayViewModel(repository: repository, timeSource: FixedTimeSource(now: now))
        await model.load()
        await model.startRecommended()

        await model.completeFocused()

        let stored = try #require(try await repository.fetch(id: TaskID("only")))
        #expect(stored.status == .completed)
        #expect(stored.completedAt == now)
    }

    @Test("completing the last task leaves an explained empty state, not a blank screen")
    func completingTheLastTaskExplainsItself() async throws {
        let model = try await loaded([task("only", deadlineHours: 2)])
        await model.startRecommended()

        await model.completeFocused()

        #expect(model.outcome == .nothingAvailable(.noActiveTasks))
    }

    @Test("rejecting a recommendation moves on to something else")
    func rejectingAdvances() async throws {
        let model = try await loaded([task("rejected", deadlineHours: 2), task("other", deadlineHours: 3)])

        await model.rejectRecommended(reason: .cantRightNow)

        #expect(try #require(model.recommendation).task.id == TaskID("other"))
    }

    @Test("a rejection is recorded in the store as history")
    func rejectionPersists() async throws {
        let repository = InMemoryTaskRepository()
        try await repository.upsert(task("only", deadlineHours: 2))
        let model = TodayViewModel(repository: repository, timeSource: FixedTimeSource(now: now))
        await model.load()

        await model.rejectRecommended(reason: .needSomethingShorter)

        let stored = try #require(try await repository.fetch(id: TaskID("only")))
        #expect(stored.rejections.map(\.reason) == [.needSomethingShorter])
    }

    @Test("a rejected task is still offered when it is the only one left, and is flagged")
    func soleRejectedTaskIsFlagged() async throws {
        let model = try await loaded([task("only", deadlineHours: 2)])

        await model.rejectRecommended(reason: .cantRightNow)

        let recommendation = try #require(model.recommendation)
        #expect(recommendation.task.id == TaskID("only"))
        #expect(recommendation.wasRecentlyRejected)
    }

    @Test("stopping Focus does not complete the task")
    func stoppingDoesNotComplete() async throws {
        let model = try await loaded([task("only", deadlineHours: 2)])
        await model.startRecommended()

        model.stopFocus()

        #expect(model.focused == nil)
        #expect(try #require(model.recommendation).task.id == TaskID("only"))
    }

    @Test("a store that cannot be read says so instead of showing an empty screen")
    func storeFailureIsSurfaced() async {
        // A student who cannot see that their tasks failed to load will assume they are gone.
        let model = TodayViewModel(
            repository: FailingTaskRepository(),
            timeSource: FixedTimeSource(now: now)
        )

        await model.load()

        #expect(model.storeFailure != nil)
    }
}

/// A store where everything fails, for the unhappy path.
private struct FailingTaskRepository: TaskRepository {
    struct Failure: Error {}

    func fetchAll() async throws -> [TaskItem] { throw Failure() }
    func fetch(id: TaskID) async throws -> TaskItem? { throw Failure() }
    func fetch(status: TaskStatus) async throws -> [TaskItem] { throw Failure() }
    func upsert(_ task: TaskItem) async throws { throw Failure() }
    func upsert(_ tasks: [TaskItem]) async throws { throw Failure() }
    func delete(id: TaskID) async throws { throw Failure() }
}

@Suite("Copy tone")
struct CopyToneTests {

    @Test("no unavailability copy shames the user")
    func unavailabilityCopyIsNeverJudgemental() {
        let banned = ["failed", "behind", "should have", "streak", "lazy", "again"]
        let reasons: [UnavailabilityReason] = [
            .noActiveTasks,
            .nothingFitsAvailableTime(shortestMinutes: 45),
            .everythingBlocked
        ]

        for reason in reasons {
            let text = (
                UnavailabilityCopy.headline(for: reason) + " "
                    + UnavailabilityCopy.detail(for: reason)
            ).lowercased()
            for word in banned {
                #expect(!text.contains(word), "'\(word)' appears in copy for \(reason)")
            }
        }
    }

    @Test("every rejection reason has a label about circumstance, not character")
    func rejectionLabelsAreAboutCircumstance() {
        let banned = ["lazy", "unmotivated", "procrastinat", "avoid"]

        for reason in RejectionReason.allCases {
            let label = RejectionCopy.label(for: reason)
            #expect(!label.isEmpty)
            for word in banned {
                #expect(!label.lowercased().contains(word), "'\(word)' in: \(label)")
            }
        }
    }
}
