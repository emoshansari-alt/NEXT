import Foundation
import Testing

@testable import NextKit

// Minimum Win (PRODUCT_SPEC.md §4.12). Once the ideal outcome is out of reach, NEXT stops
// offering it and offers the highest-value progress that genuinely fits the time left.
//
// The trigger is not reinvented here: it is `DeadlineFeasibility.unreachable`, which
// `RankingEngine` already computes. These tests pin that the planner defers to it.

private let planner = MinimumWinPlanner()

/// The worked example from the spec: a paper that cannot be finished in the time left.
///
/// Six hours of work. `dueInHours` decides how much of it is still reachable.
private func paper(estimatedMinutes: Int? = 360, dueInHours: Double?) -> TaskItem {
    makeTask(
        id: "paper",
        title: "History paper",
        deadline: dueInHours.map { Date.hoursFromReference($0) },
        estimatedMinutes: estimatedMinutes
    )
}

@Suite("Minimum Win — when it applies")
struct MinimumWinTriggerTests {

    @Test("a comfortable deadline is left alone")
    func comfortableIsNotShrunk() {
        // Sixty minutes of work with ten hours left. Shrinking the goal here would be the app
        // deciding the user is going to fall short, which is not its call to make.
        let task = paper(estimatedMinutes: 60, dueInHours: 10)
        #expect(planner.plan(for: task, now: .testReference) == .notNeeded(.comfortable))
    }

    @Test("a tight deadline is left alone")
    func tightIsNotShrunk() {
        // Still achievable. Tight means "start now", not "give up on finishing".
        let task = paper(estimatedMinutes: 60, dueInHours: 2)
        #expect(planner.plan(for: task, now: .testReference) == .notNeeded(.tight))
    }

    @Test("an undated task has no ideal outcome to lose")
    func noDeadlineIsNotShrunk() {
        let task = paper(estimatedMinutes: 360, dueInHours: nil)
        #expect(planner.plan(for: task, now: .testReference) == .notNeeded(.noDeadline))
    }

    @Test("without a duration estimate NEXT does not claim the goal is out of reach")
    func unknownDurationIsNotShrunk() {
        // The degenerate case that matters most. There is a deadline but no estimate, so
        // "you cannot finish this" would be invented certainty — forbidden by the spec.
        let task = paper(estimatedMinutes: nil, dueInHours: 2)
        #expect(planner.plan(for: task, now: .testReference) == .notNeeded(.unknownDuration))
    }

    @Test("a task with nothing but a title has no ideal outcome to lose either")
    func titleOnly() {
        // Straight out of a brain dump: a title and nothing else — no deadline, no estimate,
        // no substeps. There is no deadline to be out of reach of, so there is nothing to
        // reduce. Rescue is the surface for this, not Minimum Win.
        let task = makeTask(id: "thing", title: "Chemistry")
        #expect(planner.plan(for: task, now: .testReference) == .notNeeded(.noDeadline))

        // And it stays refused when something upstream insists otherwise: with no deadline
        // there is no window, and a window cannot be guessed at.
        let forced = Recommendation(
            task: task,
            score: ScoreBreakdown(factors: [:]),
            explanation: .nothingElsePending,
            deadlineFeasibility: .unreachable,
            wasRecentlyRejected: false
        )
        #expect(planner.plan(for: forced, now: .testReference) == .notNeeded(.noDeadline))
    }

    @Test("an unreachable deadline produces a ladder")
    func unreachableProducesALadder() {
        let task = paper(dueInHours: 5)
        let outcome = planner.plan(for: task, now: .testReference)

        guard let plan = outcome.plan else {
            Issue.record("expected a ladder, got \(outcome)")
            return
        }
        #expect(plan.taskID == TaskID("paper"))
        #expect(plan.minutesRemaining == 300)
        #expect(!plan.rungs.isEmpty)
    }
}

@Suite("Minimum Win — no time left at all")
struct MinimumWinNoTimeTests {

    @Test("a deadline that has already passed leaves nothing to fit")
    func deadlinePassed() {
        let task = paper(dueInHours: -1)
        #expect(planner.plan(for: task, now: .testReference) == .noTimeRemaining)
    }

    @Test("less than a whole minute left is no time left")
    func underAMinute() {
        let task = makeTask(
            id: "paper",
            title: "History paper",
            deadline: Date.testReference.addingTimeInterval(30),
            estimatedMinutes: 360
        )
        #expect(planner.plan(for: task, now: .testReference) == .noTimeRemaining)
    }

    @Test("exactly at the deadline leaves nothing to fit")
    func exactlyAtTheDeadline() {
        let task = makeTask(
            id: "paper",
            title: "History paper",
            deadline: .testReference,
            estimatedMinutes: 360
        )
        #expect(planner.plan(for: task, now: .testReference) == .noTimeRemaining)
    }
}

@Suite("Minimum Win — the ladder")
struct MinimumWinLadderTests {

    /// Five hours left against six hours of work: all three generic writing stages fit.
    private func fullLadder() -> MinimumWinPlan? {
        planner.plan(for: paper(dueInHours: 5), now: .testReference).plan
    }

    @Test("every rung fits the time that is actually left")
    func everyRungFits() {
        // The promise the whole feature rests on. A rung that does not fit is a lie the user
        // discovers only when the deadline arrives.
        for hours in [0.5, 1, 2, 3, 4, 5] as [Double] {
            let outcome = planner.plan(for: paper(dueInHours: hours), now: .testReference)
            guard let plan = outcome.plan else {
                Issue.record("expected a ladder \(hours)h out, got \(outcome)")
                continue
            }
            for rung in plan.rungs {
                #expect(
                    rung.minutes <= plan.minutesRemaining,
                    "\(rung.minutes) min rung offered with \(plan.minutesRemaining) min left"
                )
                #expect(rung.minutes > 0)
            }
        }
    }

    @Test("the rungs run from most ambitious to least")
    func decreasingAmbition() {
        guard let plan = fullLadder() else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.rungs.count == 3)

        for (bigger, smaller) in zip(plan.rungs, plan.rungs.dropFirst()) {
            #expect(bigger.minutes > smaller.minutes)
            #expect(bigger.steps.count > smaller.steps.count)
        }
        #expect(plan.best == plan.rungs.first)
    }

    @Test("each rung is the work of the rung below plus one more piece")
    func rungsAreCumulative() {
        // Progress is a sequence, not a menu of unrelated fragments: reaching the second
        // outcome means having reached the first one on the way.
        guard let plan = fullLadder() else {
            Issue.record("expected a ladder")
            return
        }
        for (bigger, smaller) in zip(plan.rungs, plan.rungs.dropFirst()) {
            #expect(bigger.steps.prefix(smaller.steps.count) == ArraySlice(smaller.steps))
        }
    }

    @Test("a rung asks for exactly as long as its steps take")
    func minutesAreTheSumOfTheSteps() {
        guard let plan = fullLadder() else {
            Issue.record("expected a ladder")
            return
        }
        for rung in plan.rungs where !rung.isTimeBoxed {
            #expect(rung.minutes == rung.steps.reduce(0) { $0 + $1.minutes })
        }
    }

    @Test("the top rung is the furthest the time actually reaches")
    func topRungIsTheFurthestThatFits() {
        // Three hours left. Outline (54) and introduction (72) fit at 126 minutes;
        // adding the first section (108) would need 234, so it is not offered.
        guard let plan = planner.plan(for: paper(dueInHours: 3), now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.minutesRemaining == 180)
        #expect(plan.rungs.map(\.minutes) == [126, 54])
    }

    @Test("reassessing comes after the top rung, not at the deadline")
    func reassessFollowsTheBestRung() {
        guard let plan = fullLadder() else {
            Issue.record("expected a ladder")
            return
        }
        let topRungEnds = Date.testReference.addingTimeInterval(Double(plan.best.minutes) * 60)
        #expect(plan.reassessAt == topRungEnds)
        #expect(plan.reassessAt <= Date.hoursFromReference(5))
    }
}

@Suite("Minimum Win — when only a start fits")
struct MinimumWinTimeBoxTests {

    @Test("too little time for any whole stage still offers where to spend it")
    func offersATimeBoxedStart() {
        // Thirty minutes against six hours of work. The smallest generic stage is 54 minutes,
        // so nothing completes — but "nothing fits" would be a useless thing to say.
        guard let plan = planner.plan(for: paper(dueInHours: 0.5), now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.minutesRemaining == 30)
        #expect(plan.rungs.count == 1)
        #expect(plan.best.isTimeBoxed)
        #expect(plan.best.minutes == 30)
        #expect(plan.best.leadingSteps.isEmpty)
        #expect(plan.framing == .onlyAStartFits(minutesRemaining: 30))
    }

    @Test("when whole stages fit the framing does not hedge")
    func framingReflectsWhatFits() {
        guard let plan = planner.plan(for: paper(dueInHours: 5), now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.framing == .hereIsWhatFits(minutesRemaining: 300))
        #expect(plan.rungs.allSatisfy { !$0.isTimeBoxed })
    }
}

@Suite("Minimum Win — a task with nothing but a title")
struct MinimumWinGenericTests {

    @Test("a recognisable kind of work gets that kind's stages, labelled generic")
    func inferredKindIsDeclared() {
        guard let plan = planner.plan(for: paper(dueInHours: 5), now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.source == .genericStages(.writing))
        #expect(plan.source.isGeneric)
        #expect(plan.best.steps.allSatisfy { !$0.origin.isRecordedByUser })
    }

    @Test("an unrecognisable title still gets a ladder, and says it is generic")
    func unknownKindStillLadders() {
        // Nothing but a title and the two numbers ranking needs. The stages cannot be about
        // the work itself, so they are about finding out what the work is.
        let task = makeTask(
            id: "thing",
            title: "Zzyzx",
            deadline: .hoursFromReference(5),
            estimatedMinutes: 360
        )
        guard let plan = planner.plan(for: task, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.source == .genericStages(nil))
        #expect(plan.source.isGeneric)
        #expect(plan.rungs.allSatisfy { !$0.steps.isEmpty })
    }

    @Test("stage lengths are shares of the estimate the user gave")
    func stagesAreSharesOfTheEstimate() {
        guard let plan = planner.plan(for: paper(dueInHours: 5), now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        // 15% / 20% / 30% of 360 minutes.
        #expect(plan.best.steps.map(\.minutes) == [54, 72, 108])
        #expect(plan.best.steps.allSatisfy { !$0.hasRecordedDuration })
    }

    @Test("a very short estimate still yields usable stage lengths")
    func stagesNeverCollapseToNothing() {
        // Ten minutes of work due in four. Fifteen percent of ten rounds to two, which is not
        // a length anyone can act on, so the floor applies.
        let task = makeTask(
            id: "note",
            title: "History paper",
            deadline: Date.testReference.addingTimeInterval(4 * 60),
            estimatedMinutes: 10
        )
        guard let plan = planner.plan(for: task, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        let floor = MinimumWinWeights.default.minimumStageMinutes
        #expect(plan.best.steps.allSatisfy { $0.minutes >= floor })
        #expect(plan.best.minutes <= plan.minutesRemaining)
    }
}

@Suite("Minimum Win — determinism")
struct MinimumWinDeterminismTests {

    @Test("the same question twice gets the same answer")
    func repeatable() {
        let task = paper(dueInHours: 5)
        let first = planner.plan(for: task, now: .testReference)
        let second = planner.plan(for: task, now: .testReference)
        #expect(first == second)
    }

    @Test("planning from a recommendation reuses the feasibility it already carries")
    func planningFromARecommendation() {
        // The integration point: ranking already decided the goal is out of reach, so the
        // planner must not recompute a different answer from the same facts.
        let task = paper(dueInHours: 5)
        let outcome = RankingEngine().recommend(
            from: [task],
            context: RankingContext(now: .testReference)
        )
        guard let recommendation = outcome.recommendation else {
            Issue.record("expected a recommendation, got \(outcome)")
            return
        }
        #expect(recommendation.deadlineFeasibility == .unreachable)
        #expect(
            planner.plan(for: recommendation, now: .testReference)
                == planner.plan(for: task, now: .testReference)
        )
    }

    @Test("a caller claiming unreachable for an undated task is refused, not guessed at")
    func undatedRecommendationIsRefused() {
        let task = paper(estimatedMinutes: 360, dueInHours: nil)
        let recommendation = Recommendation(
            task: task,
            score: ScoreBreakdown(factors: [:]),
            explanation: .nothingElsePending,
            deadlineFeasibility: .unreachable,
            wasRecentlyRejected: false
        )
        #expect(planner.plan(for: recommendation, now: .testReference) == .notNeeded(.noDeadline))
    }
}
