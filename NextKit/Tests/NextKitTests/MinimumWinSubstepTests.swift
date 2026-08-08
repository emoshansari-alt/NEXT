import Foundation
import Testing

@testable import NextKit

// Using the decomposition the user already recorded is the strongest signal Minimum Win has.
// A generic stage is a guess about the shape of somebody else's assignment; a substep the user
// wrote is not a guess at all, so it wins outright.

private let planner = MinimumWinPlanner()

private let paperID = TaskID("paper")

private func paper(estimatedMinutes: Int = 360, dueInHours: Double = 5) -> TaskItem {
    makeTask(
        id: "paper",
        title: "History paper",
        deadline: .hoursFromReference(dueInHours),
        estimatedMinutes: estimatedMinutes
    )
}

private func substep(
    _ id: String,
    _ title: String,
    minutes: Int? = nil,
    status: TaskStatus = .active,
    nextAction: String? = nil,
    createdAtHours: Double = 0
) -> TaskItem {
    makeTask(
        id: id,
        title: title,
        status: status,
        estimatedMinutes: minutes,
        nextAction: nextAction,
        parentID: paperID,
        createdAt: .hoursFromReference(createdAtHours)
    )
}

@Suite("Minimum Win — a task that already has substeps")
struct MinimumWinSubstepTests {

    /// Four recorded substeps, in creation order, totalling 220 of the 300 minutes left.
    private func decomposedPaper() -> [TaskItem] {
        [
            paper(),
            substep("s1", "Find three sources", minutes: 40, createdAtHours: -4),
            substep("s2", "Write the outline", minutes: 30, createdAtHours: -3),
            substep("s3", "Draft the introduction", minutes: 60, createdAtHours: -2),
            substep("s4", "Write section one", minutes: 90, createdAtHours: -1)
        ]
    }

    @Test("the ladder is built from the substeps, not from generic stages")
    func substepsWin() {
        let all = decomposedPaper()
        guard let plan = planner.plan(for: all[0], among: all, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }

        #expect(plan.source == .recordedSubsteps)
        #expect(!plan.source.isGeneric)
        #expect(plan.best.steps.allSatisfy { $0.origin.isRecordedByUser })
        #expect(plan.best.goal.origin == .substep(TaskID("s4")))
        #expect(
            plan.best.steps.map(\.text) == [
                "Find three sources.",
                "Write the outline.",
                "Draft the introduction.",
                "Write section one."
            ]
        )
    }

    @Test("recorded substep durations are used as they are")
    func recordedDurationsAreUsed() {
        let all = decomposedPaper()
        guard let plan = planner.plan(for: all[0], among: all, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.best.steps.map(\.minutes) == [40, 30, 60, 90])
        #expect(plan.best.steps.allSatisfy { $0.hasRecordedDuration })
        #expect(plan.best.minutes == 220)
    }

    @Test("a long decomposition is offered as a spread of sizes, not a menu")
    func longDecompositionIsCapped() {
        // Four substeps all fit, but the ladder is itself a decision (P1). Three rungs,
        // spread from the whole thing down to the first step.
        let all = decomposedPaper()
        guard let plan = planner.plan(for: all[0], among: all, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.rungs.count == MinimumWinWeights.default.maximumRungs)
        #expect(plan.rungs.map(\.minutes) == [220, 130, 40])
        #expect(plan.rungs.map { $0.steps.count } == [4, 3, 1])
    }

    @Test("substeps with no duration are budgeted out of the estimate the user did give")
    func unestimatedSubstepsAreAllocated() {
        // Five hours of work, three recorded steps, none of them timed. Splitting the one
        // number the user gave is an allocation, not knowledge — and the step says so.
        let all = [
            paper(estimatedMinutes: 300, dueInHours: 4),
            substep("a", "Read the primary source", createdAtHours: -3),
            substep("b", "Take notes on it", createdAtHours: -2),
            substep("c", "Draft the argument", createdAtHours: -1)
        ]
        guard let plan = planner.plan(for: all[0], among: all, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.best.steps.map(\.minutes) == [100, 100])
        #expect(plan.best.steps.allSatisfy { !$0.hasRecordedDuration })
        #expect(plan.rungs.map(\.minutes) == [200, 100])
    }

    @Test("a mix of timed and untimed substeps splits only what is left over")
    func mixedDurationsShareTheRemainder() {
        // 300 minutes total, one step known to be 60, so 240 is split between the other two.
        let all = [
            paper(estimatedMinutes: 300, dueInHours: 4),
            substep("a", "Read the primary source", createdAtHours: -3),
            substep("b", "Take notes on it", minutes: 60, createdAtHours: -2),
            substep("c", "Draft the argument", createdAtHours: -1)
        ]
        guard let plan = planner.plan(for: all[0], among: all, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.best.steps.map(\.minutes) == [120, 60])
        #expect(plan.best.steps.map(\.hasRecordedDuration) == [false, true])
    }

    @Test("finished substeps are not offered as things still to do")
    func completedSubstepsAreSkipped() {
        let all = [
            paper(estimatedMinutes: 300, dueInHours: 4),
            substep("a", "Find three sources", minutes: 40, status: .completed, createdAtHours: -3),
            substep("b", "Write the outline", minutes: 30, createdAtHours: -2),
            substep(
                "c",
                "Draft the introduction",
                minutes: 60,
                status: .archived,
                createdAtHours: -1
            )
        ]
        guard let plan = planner.plan(for: all[0], among: all, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.best.steps.map(\.text) == ["Write the outline."])
        #expect(plan.best.goal.origin == .substep(TaskID("b")))
    }

    @Test("a substep's own recorded next action beats its title")
    func nextActionBeatsTitle() {
        let all = [
            paper(estimatedMinutes: 300, dueInHours: 4),
            substep(
                "a",
                "Sources",
                minutes: 40,
                nextAction: "Open the library catalogue and search the reading list",
                createdAtHours: -1
            )
        ]
        guard let plan = planner.plan(for: all[0], among: all, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(
            plan.best.goal.text == "Open the library catalogue and search the reading list."
        )
    }

    @Test("substeps of some other task are not borrowed")
    func otherTasksChildrenAreIgnored() {
        let all = [
            paper(),
            makeTask(id: "x", title: "Buy milk", parentID: TaskID("shopping"))
        ]
        guard let plan = planner.plan(for: all[0], among: all, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.source == .genericStages(.writing))
    }

    @Test("substeps with nothing written in them fall back to the generic stages")
    func emptySubstepsFallBack() {
        let all = [
            paper(),
            substep("a", "   ", createdAtHours: -2),
            substep("b", "\n", createdAtHours: -1)
        ]
        guard let plan = planner.plan(for: all[0], among: all, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.source == .genericStages(.writing))
    }

    @Test("when not even the first substep fits, the window itself is offered")
    func timeBoxedAgainstRecordedWork() {
        let all = [
            paper(estimatedMinutes: 360, dueInHours: 0.25),
            substep("a", "Find three sources", minutes: 40, createdAtHours: -1)
        ]
        guard let plan = planner.plan(for: all[0], among: all, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.minutesRemaining == 15)
        #expect(plan.best.isTimeBoxed)
        #expect(plan.best.minutes == 15)
        #expect(plan.best.goal.text == "Find three sources.")
        #expect(plan.framing == .onlyAStartFits(minutesRemaining: 15))
    }

    @Test("the answer does not depend on the order the tasks arrive in")
    func orderIndependent() {
        // Two substeps created at the same instant, so only the identifier tie-break can
        // decide — exactly the hidden non-determinism D-007 exists to prevent.
        let parent = paper(estimatedMinutes: 300, dueInHours: 4)
        let a = substep("a", "Read the primary source", minutes: 50, createdAtHours: -1)
        let b = substep("b", "Take notes on it", minutes: 50, createdAtHours: -1)

        let forwards = planner.plan(for: parent, among: [parent, a, b], now: .testReference)
        let backwards = planner.plan(for: parent, among: [b, a, parent], now: .testReference)

        #expect(forwards == backwards)
        #expect(forwards.plan?.best.steps.map(\.text) == [
            "Read the primary source.",
            "Take notes on it."
        ])
    }
}
