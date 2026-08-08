import Foundation
import Testing

@testable import NextApp
import NextKit

// Tier 2 unit tests. These run on the iOS Simulator and cover the app layer's own logic —
// the wiring between the engine and the screen. Engine behaviour itself is covered at
// Tier 1 in NextKit and is not re-tested here.

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

    @Test("recommends the most urgent task on launch")
    func recommendsOnLaunch() throws {
        let model = TodayViewModel(
            tasks: [task("later", deadlineHours: 72), task("sooner", deadlineHours: 4)],
            now: now
        )

        #expect(try #require(model.recommendation).task.id == TaskID("sooner"))
    }

    @Test("with no tasks it reports nothing to do rather than crashing")
    func emptyStateIsHandled() {
        let model = TodayViewModel(tasks: [], now: now)

        #expect(model.outcome == .nothingToDo)
        #expect(model.recommendation == nil)
    }

    @Test("START opens Focus on the recommended task")
    func startOpensFocus() throws {
        let model = TodayViewModel(tasks: [task("only", deadlineHours: 4)], now: now)

        model.startRecommended()

        #expect(try #require(model.focused).id == TaskID("only"))
    }

    @Test("completing the focused task closes Focus and recommends the next thing")
    func completingAdvancesTheLoop() throws {
        // This is the core loop: START, DONE, NEXT.
        let model = TodayViewModel(
            tasks: [task("first", deadlineHours: 2), task("second", deadlineHours: 6)],
            now: now
        )
        model.startRecommended()

        model.completeFocused(now: now)

        #expect(model.focused == nil)
        #expect(try #require(model.recommendation).task.id == TaskID("second"))
    }

    @Test("completing the last task leaves an explained empty state, not a blank screen")
    func completingTheLastTaskExplainsItself() {
        let model = TodayViewModel(tasks: [task("only", deadlineHours: 2)], now: now)
        model.startRecommended()

        model.completeFocused(now: now)

        #expect(model.outcome == .nothingAvailable(.noActiveTasks))
    }

    @Test("rejecting a recommendation moves on to something else")
    func rejectingAdvances() throws {
        let model = TodayViewModel(
            tasks: [task("rejected", deadlineHours: 2), task("other", deadlineHours: 3)],
            now: now
        )

        model.rejectRecommended(reason: .cantRightNow, now: now)

        #expect(try #require(model.recommendation).task.id == TaskID("other"))
    }

    @Test("a rejected task is still offered when it is the only one left, and is flagged")
    func soleRejectedTaskIsFlagged() throws {
        let model = TodayViewModel(tasks: [task("only", deadlineHours: 2)], now: now)

        model.rejectRecommended(reason: .cantRightNow, now: now)

        let recommendation = try #require(model.recommendation)
        #expect(recommendation.task.id == TaskID("only"))
        #expect(recommendation.wasRecentlyRejected)
    }

    @Test("stopping Focus does not complete the task")
    func stoppingDoesNotComplete() throws {
        let model = TodayViewModel(tasks: [task("only", deadlineHours: 2)], now: now)
        model.startRecommended()

        model.stopFocus()

        #expect(model.focused == nil)
        #expect(try #require(model.recommendation).task.id == TaskID("only"))
    }
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
