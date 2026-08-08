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
        guard let reassessAt = plan.reassessAt else {
            Issue.record("a ladder of whole outcomes should say when to look again")
            return
        }
        #expect(reassessAt == topRungEnds)
        #expect(reassessAt < Date.hoursFromReference(5))
    }

    @Test("a time-boxed rung offers no reassess point rather than one on the deadline")
    func timeBoxedHasNothingToReassessWith() {
        // "Reassess" means looking again once real progress exists and there is still a
        // decision left to make. A time-boxed rung is the whole remaining window, so its end
        // and the deadline are the same instant — 09:30 here — and at that instant there is
        // nothing left to decide. `nil` says that; a date sitting on the deadline would claim
        // a decision point the user does not have.
        guard let plan = planner.plan(for: paper(dueInHours: 0.5), now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.best.isTimeBoxed)
        #expect(plan.reassessAt == nil)
    }

    @Test("wherever there is a reassess point, it falls strictly before the deadline")
    func anyReassessPointLeavesTimeToAct() {
        // The property behind both cases above, swept across the whole range of windows: a
        // reassess point is only offered when acting on it is still possible.
        for hours in [0.25, 0.5, 1, 2, 3, 4, 5] as [Double] {
            let outcome = planner.plan(for: paper(dueInHours: hours), now: .testReference)
            guard let plan = outcome.plan else {
                Issue.record("expected a ladder \(hours)h out, got \(outcome)")
                continue
            }
            guard let reassessAt = plan.reassessAt else {
                #expect(plan.best.isTimeBoxed, "a whole-outcome rung should offer a reassess")
                continue
            }
            #expect(!plan.best.isTimeBoxed)
            #expect(reassessAt > Date.testReference)
            #expect(
                reassessAt < Date.hoursFromReference(hours),
                "reassess at \(reassessAt) with the deadline at \(hours)h"
            )
        }
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
        // Twenty-eight minutes of work with twenty minutes left, chosen so that a whole
        // three-rung ladder is actually built and the floor is load-bearing inside it: 15% of
        // 28 is 4.2, which is not a length anyone can act on, so the floor lifts it to 5,
        // while 20% and 30% come to 6 and 8 and stand as they are.
        //
        // The window matters. Against a window too small for any whole stage the planner
        // returns the time-boxed rung, and every claim about stage lengths then passes without
        // a single stage length having been examined — which is what this test used to do.
        // The minutes below are therefore written as literals rather than compared against
        // `minimumStageMinutes`: a test that reads the same constant the planner reads moves
        // with it, and would keep passing if the floor were lowered to zero.
        let task = makeTask(
            id: "note",
            title: "History paper",
            deadline: Date.testReference.addingTimeInterval(20 * 60),
            estimatedMinutes: 28
        )
        guard let plan = planner.plan(for: task, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.minutesRemaining == 20)
        #expect(!plan.best.isTimeBoxed)
        #expect(plan.best.steps.map(\.minutes) == [5, 6, 8])
        #expect(plan.rungs.map(\.minutes) == [19, 11, 5])
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

    @Test("a caller claiming unreachable for an unestimated task is refused too")
    func unestimatedRecommendationIsRefused() {
        // The mirror of the case above, and it matters for the same reason. "Unreachable"
        // means the work does not fit the window, which is a claim about a duration; with no
        // estimate there is no duration and the claim is unsupported.
        //
        // Planning anyway is worse than merely unhelpful. The stage budget is a share of the
        // estimate, so with no estimate every stage collapses to the five-minute floor and the
        // user is shown "You have 5 hours left. Here is what fits." above a fifteen-minute
        // ladder — a number the app does not have, dressed up as advice. Declining is the only
        // honest answer, exactly as for a missing deadline.
        let task = paper(estimatedMinutes: nil, dueInHours: 5)
        let recommendation = Recommendation(
            task: task,
            score: ScoreBreakdown(factors: [:]),
            explanation: .nothingElsePending,
            deadlineFeasibility: .unreachable,
            wasRecentlyRejected: false
        )
        #expect(
            planner.plan(for: recommendation, now: .testReference)
                == .notNeeded(.unknownDuration)
        )
    }

    @Test("an unestimated task with substeps is refused as well")
    func unestimatedRecommendationWithSubstepsIsRefused() {
        // Recorded substeps do not rescue the claim. Whether the ladder would have come from
        // the user's own decomposition or from generic stages is a question about *what* to
        // offer; the guard is about whether there is any basis for offering a reduced goal at
        // all, and an unsupported "you cannot finish this" is unsupported either way.
        let parent = paper(estimatedMinutes: nil, dueInHours: 5)
        let child = makeTask(
            id: "s1",
            title: "Find three sources",
            estimatedMinutes: 40,
            parentID: TaskID("paper"),
            createdAt: .hoursFromReference(-1)
        )
        let recommendation = Recommendation(
            task: parent,
            score: ScoreBreakdown(factors: [:]),
            explanation: .nothingElsePending,
            deadlineFeasibility: .unreachable,
            wasRecentlyRejected: false
        )
        #expect(
            planner.plan(for: recommendation, among: [parent, child], now: .testReference)
                == .notNeeded(.unknownDuration)
        )
    }
}
