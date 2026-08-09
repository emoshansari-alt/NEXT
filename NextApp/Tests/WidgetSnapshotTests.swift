import Foundation
import Testing

@testable import NextApp
import NextKit

private let reference = Date(timeIntervalSince1970: 1_773_133_200)  // 2026-03-10 09:00 UTC

private struct FixedTimeSource: TimeSource {
    let now: Date
}

private func task(
    _ id: String,
    title: String,
    nextAction: String? = nil,
    deadlineHours: Double? = nil,
    minutes: Int? = nil
) -> TaskItem {
    TaskItem(
        id: TaskID(id),
        title: title,
        createdAt: reference,
        deadline: deadlineHours.map { reference.addingTimeInterval($0 * 3600) },
        estimatedMinutes: minutes,
        nextAction: nextAction
    )
}

private func recommendation(for item: TaskItem) throws -> RecommendationOutcome {
    RankingEngine().recommend(from: [item], context: RankingContext(now: reference))
}

@Suite("SnapshotStore — the shared container")
struct SnapshotStoreTests {

    // The App Group experiment, and its answer.
    //
    // This suite originally asserted the container resolves. On an unsigned Simulator build it
    // does not: `containerURL(forSecurityApplicationGroupIdentifier:)` returns nil, because App
    // Groups are provisioned entitlements and there is no profile granting one. That is a real
    // finding rather than a defect, and it is recorded in RELEASE_GATED.md Gate B — the widget
    // cannot be verified end to end until the project is signed.
    //
    // So the tests assert what is actually true in each world: with a container, the round trip
    // must work; without one, the degradation must be silent and safe. Both branches assert
    // something real, and the day signing arrives the first branch starts running for free.

    @Test("with a shared container, a snapshot written by the app reads back identically")
    func snapshotRoundTripsWhenContainerExists() throws {
        let store = SnapshotStore()
        try withKnownIssue("App Groups need a provisioning profile; see RELEASE_GATED.md Gate B") {
            try #require(store.containerIsAvailable)
        }

        guard store.containerIsAvailable else { return }
        defer { store.clear() }

        let written = RecommendationSnapshot(
            generatedAt: reference,
            taskID: TaskID("chem"),
            taskTitle: "Chemistry worksheet",
            headline: "Do questions 1 to 5.",
            detail: "Due tomorrow · ~15 min"
        )
        store.write(written)

        #expect(store.read() == written)
    }

    @Test("without a shared container, the app degrades silently instead of failing")
    func missingContainerIsHarmless() {
        // This is the branch that actually runs today, and it is the one that matters: a widget
        // that cannot be updated must never become a problem the user sees. Writing is a no-op,
        // reading is nil, and nothing throws or traps.
        let store = SnapshotStore(appGroup: "group.deliberately.nonexistent")

        #expect(store.containerIsAvailable == false)

        store.write(
            RecommendationSnapshot(
                generatedAt: reference,
                taskID: TaskID("chem"),
                taskTitle: "Chemistry worksheet",
                headline: "Do questions 1 to 5.",
                detail: nil
            )
        )

        #expect(store.read() == nil)
        store.clear()
    }

    @Test("publishing without a container does not disturb the app")
    func publishingIsSafeWithoutAContainer() {
        // The publisher is called on every load and every write. If an unavailable container
        // could throw or trap, the whole Today screen would go down with the widget.
        let publisher = SnapshotPublisher(
            store: SnapshotStore(appGroup: "group.deliberately.nonexistent"),
            reloadTimelines: {}
        )

        publisher.publish(.nothingToDo, at: reference)
    }
}

@Suite("SnapshotPublisher — what the widget is told")
struct SnapshotPublisherTests {

    @Test("a recommendation becomes the action, its task, and its detail")
    func recommendationBecomesSnapshot() throws {
        let chem = task(
            "chem", title: "Chemistry worksheet",
            nextAction: "Do questions 1 to 5.", deadlineHours: 30, minutes: 15
        )

        let snapshot = SnapshotPublisher.snapshot(
            for: try recommendation(for: chem), at: reference
        )

        #expect(snapshot.taskID == TaskID("chem"))
        #expect(snapshot.taskTitle == "Chemistry worksheet")
        #expect(snapshot.headline == "Do questions 1 to 5.")
        #expect(snapshot.detail?.contains("15 min") == true)
        #expect(snapshot.hasWork)
    }

    @Test("the task name is omitted when it would just repeat the action")
    func titleOmittedWhenRedundant() throws {
        // A task with no recorded first step uses its own title as the action. Printing it
        // twice would waste the one line a small widget has.
        let email = task("email", title: "Email Professor Adeyemi")

        let snapshot = SnapshotPublisher.snapshot(
            for: try recommendation(for: email), at: reference
        )

        #expect(snapshot.headline == "Email Professor Adeyemi")
        #expect(snapshot.taskTitle == nil)
    }

    @Test("an empty store produces an empty snapshot, not a stale one")
    func emptyOutcomeBecomesEmptySnapshot() {
        let snapshot = SnapshotPublisher.snapshot(for: .nothingToDo, at: reference)

        #expect(snapshot.hasWork == false)
        #expect(snapshot.taskID == nil)
        #expect(snapshot.headline == UnavailabilityCopy.emptyHeadline)
    }

    @Test("the widget and Today use the same words")
    func copyMatchesTheApp() {
        // Two surfaces describing the same state differently is how a user learns not to trust
        // either. Both read from UnavailabilityCopy.
        let snapshot = SnapshotPublisher.snapshot(
            for: .nothingAvailable(.noActiveTasks), at: reference
        )

        #expect(snapshot.headline == UnavailabilityCopy.headline(for: .noActiveTasks))
        #expect(snapshot.detail == UnavailabilityCopy.detail(for: .noActiveTasks))
    }

    @Test("the snapshot links to the task it is about")
    func snapshotLinksToItsTask() throws {
        let chem = task("chem", title: "Chemistry worksheet", nextAction: "Start.")

        let snapshot = SnapshotPublisher.snapshot(
            for: try recommendation(for: chem), at: reference
        )
        let link = try #require(snapshot.deepLink)

        #expect(DeepLink(url: link) == .task(TaskID("chem")))
    }
}

@MainActor
@Suite("TodayViewModel — deep links")
struct TodayDeepLinkTests {

    private func loaded(_ tasks: [TaskItem]) async throws -> TodayViewModel {
        let repository = InMemoryTaskRepository()
        for task in tasks { try await repository.upsert(task) }

        let model = TodayViewModel(
            repository: repository,
            timeSource: FixedTimeSource(now: reference)
        )
        await model.load()
        return model
    }

    @Test("a task link opens that task")
    func taskLinkOpensTheTask() async throws {
        let model = try await loaded([task("chem", title: "Chemistry worksheet")])

        await model.open(.task(TaskID("chem")))

        #expect(model.linkedTask?.id == TaskID("chem"))
    }

    @Test("a link to a deleted task leaves the user on Today rather than erroring")
    func staleLinkIsHarmless() async throws {
        // Reachable in normal use: a widget can be minutes stale and a reminder can outlive the
        // thing it was about.
        let model = try await loaded([task("chem", title: "Chemistry worksheet")])

        await model.open(.task(TaskID("deleted-long-ago")))

        #expect(model.linkedTask == nil)
        #expect(model.recommendation != nil, "Today is still usable")
    }

    @Test("the plain app link just shows Today")
    func todayLinkShowsToday() async throws {
        let model = try await loaded([task("chem", title: "Chemistry worksheet")])
        await model.open(.task(TaskID("chem")))

        await model.open(.today)

        #expect(model.linkedTask == nil)
    }
}
