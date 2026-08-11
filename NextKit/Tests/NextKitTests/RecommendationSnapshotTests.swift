import Foundation
import Testing

@testable import NextKit

// What the widget shows. A tiny Codable value the app writes and the widget reads, rather than
// the widget opening the SwiftData store itself: widget extensions run under a hard memory
// limit, and a snapshot is a few hundred bytes against a whole database and its schema.

private let reference = Date.testReference

@Suite("RecommendationSnapshot — contents")
struct RecommendationSnapshotContentTests {

    @Test("a snapshot with work carries what the widget needs and nothing else")
    func snapshotWithWork() {
        let snapshot = RecommendationSnapshot(
            generatedAt: reference,
            taskID: TaskID("chem"),
            taskTitle: "Chemistry worksheet",
            headline: "Do questions 1 to 5.",
            detail: "Due tomorrow · ~15 min"
        )

        #expect(snapshot.hasWork)
        #expect(snapshot.taskID == TaskID("chem"))
    }

    @Test("an empty snapshot has no task and says so")
    func emptySnapshot() {
        let snapshot = RecommendationSnapshot.nothingToDo(
            generatedAt: reference,
            headline: "Nothing here yet.",
            detail: "Add what is on your mind."
        )

        #expect(snapshot.hasWork == false)
        #expect(snapshot.taskID == nil)
        #expect(snapshot.taskTitle == nil)
    }

    @Test("a snapshot round trips through JSON")
    func snapshotRoundTrips() throws {
        // It crosses a process boundary as bytes, so this is the actual contract between the
        // app and the widget, not an implementation detail.
        let original = RecommendationSnapshot(
            generatedAt: reference,
            taskID: TaskID("chem"),
            taskTitle: "Chemistry worksheet",
            headline: "Do questions 1 to 5.",
            detail: "Due tomorrow"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecommendationSnapshot.self, from: data)

        #expect(decoded == original)
    }
}

@Suite("RecommendationSnapshot — staleness")
struct RecommendationSnapshotStalenessTests {

    @Test("a fresh snapshot is not stale")
    func freshIsNotStale() {
        let snapshot = RecommendationSnapshot.nothingToDo(
            generatedAt: reference, headline: "x", detail: nil
        )

        #expect(snapshot.isStale(at: reference.addingTimeInterval(3600)) == false)
    }

    @Test("a snapshot from yesterday is stale")
    func yesterdayIsStale() {
        // A widget showing a recommendation worked out two days ago is not showing the
        // recommendation — it is showing history, and the user cannot tell the difference.
        let snapshot = RecommendationSnapshot.nothingToDo(
            generatedAt: reference, headline: "x", detail: nil
        )

        #expect(snapshot.isStale(at: reference.addingTimeInterval(48 * 3600)))
    }

    @Test("the staleness horizon is exactly the documented one")
    func horizonIsExact() {
        let snapshot = RecommendationSnapshot.nothingToDo(
            generatedAt: reference, headline: "x", detail: nil
        )
        let horizon = RecommendationSnapshot.stalenessHorizon

        #expect(snapshot.isStale(at: reference.addingTimeInterval(horizon - 1)) == false)
        #expect(snapshot.isStale(at: reference.addingTimeInterval(horizon + 1)))
    }

    @Test("a snapshot from the future is not treated as stale")
    func futureIsNotStale() {
        // Reachable from a clock change or a time-zone move. Treating it as stale would blank
        // the widget for a reason the user cannot see or fix.
        let snapshot = RecommendationSnapshot.nothingToDo(
            generatedAt: reference, headline: "x", detail: nil
        )

        #expect(snapshot.isStale(at: reference.addingTimeInterval(-7200)) == false)
    }
}

@Suite("RecommendationSnapshot — deep links")
struct RecommendationSnapshotLinkTests {

    @Test("a snapshot with a task links to that task")
    func taskLink() throws {
        let snapshot = RecommendationSnapshot(
            generatedAt: reference,
            taskID: TaskID("chem"),
            taskTitle: "Chemistry worksheet",
            headline: "Do questions 1 to 5.",
            detail: nil
        )

        #expect(snapshot.deepLink == URL(string: "next://task/chem"))
    }

    @Test("an empty snapshot links to the app itself")
    func emptyLinksHome() {
        let snapshot = RecommendationSnapshot.nothingToDo(
            generatedAt: reference, headline: "x", detail: nil
        )

        #expect(snapshot.deepLink == URL(string: "next://today"))
    }

    @Test("an identifier needing escaping still produces a usable link")
    func identifiersAreEscaped() throws {
        // Identifiers are UUID strings in production, but the type does not promise that, and a
        // link that silently fails to parse would open nothing at all.
        let snapshot = RecommendationSnapshot(
            generatedAt: reference,
            taskID: TaskID("a b/c?d"),
            taskTitle: "Odd",
            headline: "Do it.",
            detail: nil
        )

        let link = try #require(snapshot.deepLink)
        #expect(DeepLink(url: link) == .task(TaskID("a b/c?d")))
    }
}

@Suite("Widget link — where a tap actually lands")
struct WidgetLinkTests {

    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(taskID: TaskID?, generatedAt: Date) -> RecommendationSnapshot {
        RecommendationSnapshot(
            generatedAt: generatedAt,
            taskID: taskID,
            taskTitle: taskID == nil ? nil : "History essay",
            headline: "Find three sources.",
            detail: nil
        )
    }

    @Test("a fresh snapshot links to the task it is showing")
    func freshLinksToItsTask() {
        let fresh = snapshot(taskID: TaskID("chem"), generatedAt: reference)

        #expect(fresh.link(at: reference) == URL(string: "next://task/chem"))
    }

    @Test("a stale snapshot links to Today, not to the task it has stopped showing")
    func staleLinksHome() {
        // The widget stops drawing a stale snapshot and shows "Open NEXT to see what is next."
        // Sending the tap to a specific task anyway would act on a recommendation the widget is
        // no longer making, and the reader would have no way to tell where it came from. Today is
        // the one screen that recomputes.
        let stale = snapshot(
            taskID: TaskID("chem"),
            generatedAt: reference.addingTimeInterval(-RecommendationSnapshot.stalenessHorizon - 1)
        )

        #expect(stale.link(at: reference) == URL(string: "next://today"))
        #expect(stale.deepLink == URL(string: "next://task/chem"), "the raw link is unchanged")
    }

    @Test("the staleness boundary itself still links to the task")
    func theBoundaryIsNotStale() {
        // `isStale` is a strict `>`, and the two must not disagree about the same instant: a
        // widget that still draws a snapshot must still link to it.
        let edge = snapshot(
            taskID: TaskID("chem"),
            generatedAt: reference.addingTimeInterval(-RecommendationSnapshot.stalenessHorizon)
        )

        #expect(edge.isStale(at: reference) == false)
        #expect(edge.link(at: reference) == URL(string: "next://task/chem"))
    }

    @Test("a snapshot with nothing to do links to Today whether or not it is stale")
    func emptyAlwaysLinksHome() {
        let empty = RecommendationSnapshot.nothingToDo(
            generatedAt: reference, headline: "Nothing yet.", detail: nil
        )
        let old = RecommendationSnapshot.nothingToDo(
            generatedAt: reference.addingTimeInterval(-10 * 24 * 3600),
            headline: "Nothing yet.",
            detail: nil
        )

        #expect(empty.link(at: reference) == URL(string: "next://today"))
        #expect(old.link(at: reference) == URL(string: "next://today"))
    }

    @Test("a snapshot dated in the future links to its task rather than being treated as old")
    func aFutureSnapshotIsNotStale() {
        // Reachable from a clock change or a time-zone move. Sending the user somewhere else for
        // a reason they can neither see nor fix would be worse than a slightly odd timestamp.
        let ahead = snapshot(taskID: TaskID("chem"), generatedAt: reference.addingTimeInterval(3600))

        #expect(ahead.link(at: reference) == URL(string: "next://task/chem"))
    }
}

@Suite("DeepLink — parsing")
struct DeepLinkTests {

    @Test("a task link parses back to its identifier")
    func taskLinkParses() throws {
        let url = try #require(URL(string: "next://task/chem"))

        #expect(DeepLink(url: url) == .task(TaskID("chem")))
    }

    @Test("the bare app link opens Today")
    func todayLinkParses() throws {
        let url = try #require(URL(string: "next://today"))

        #expect(DeepLink(url: url) == .today)
    }

    @Test("anything unrecognised is rejected rather than guessed at")
    func unknownLinksAreRejected() throws {
        // A link this app does not understand must not be interpreted as one it does. Opening
        // the wrong task because a URL nearly matched would be worse than ignoring it.
        for raw in ["next://", "next://nonsense", "https://example.com/task/chem", "next://task/"] {
            let url = try #require(URL(string: raw))
            #expect(DeepLink(url: url) == nil, "\(raw) should not parse")
        }
    }
}
