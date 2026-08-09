import Foundation
import Testing

@testable import NextKit

// Backs Rescue's "I don't have enough time" path (PRODUCT_SPEC.md §4.11): the user states a
// window, and NEXT picks the highest-value thing genuinely achievable inside it. Offering
// something that does not fit would be worse than offering nothing.

@Suite("RankingEngine — available time")
struct RankingTimeBudgetTests {

    let engine = RankingEngine()

    private func context(minutes: Int?) -> RankingContext {
        RankingContext(now: .testReference, availableMinutes: minutes)
    }

    @Test("with no stated time budget, long tasks remain eligible")
    func noBudgetMeansNoTimeFilter() throws {
        let long = makeTask(id: "long", deadline: .daysFromReference(1), estimatedMinutes: 240)

        let outcome = engine.recommend(from: [long], context: context(minutes: nil))

        #expect(try #require(outcome.recommendation).task.id == long.id)
    }

    @Test("a task longer than the available window is not recommended")
    func tooLongIsFiltered() throws {
        let tooLong = makeTask(
            id: "long", deadline: .hoursFromReference(2), estimatedMinutes: 120
        )
        let fits = makeTask(id: "fits", deadline: .daysFromReference(4), estimatedMinutes: 10)

        let outcome = engine.recommend(from: [tooLong, fits], context: context(minutes: 15))

        // The long task is far more urgent, so only the time filter can explain this result.
        #expect(try #require(outcome.recommendation).task.id == fits.id)
    }

    @Test("a task exactly filling the window is eligible")
    func exactFitIsEligible() throws {
        let exact = makeTask(id: "exact", estimatedMinutes: 15)

        let outcome = engine.recommend(from: [exact], context: context(minutes: 15))

        #expect(try #require(outcome.recommendation).task.id == exact.id)
    }

    @Test("a task with no estimate is not hidden by a time budget")
    func unestimatedTaskSurvivesTheFilter() throws {
        // Excluding unestimated work would silently hide most of what a student captures.
        // Unknown duration is treated as "might fit", not "does not fit".
        let unestimated = makeTask(id: "unknown", estimatedMinutes: nil)

        let outcome = engine.recommend(from: [unestimated], context: context(minutes: 5))

        #expect(try #require(outcome.recommendation).task.id == unestimated.id)
    }

    @Test("when nothing fits the window, the engine says so and names the shortest task")
    func nothingFitsIsExplained() {
        let a = makeTask(id: "a", estimatedMinutes: 90)
        let b = makeTask(id: "b", estimatedMinutes: 45)
        let c = makeTask(id: "c", estimatedMinutes: 120)

        let outcome = engine.recommend(from: [a, b, c], context: context(minutes: 15))

        // Naming the shortest lets the UI say something useful — "the shortest thing you have
        // is 45 minutes" — instead of an unexplained empty screen.
        #expect(outcome == .nothingAvailable(.nothingFitsAvailableTime(shortestMinutes: 45)))
    }

    @Test("a task that uses more of the window scores a better contextual fit")
    func fillingTheWindowScoresHigher() {
        let barelyUses = makeTask(id: "short", estimatedMinutes: 5)
        let fillsIt = makeTask(id: "full", estimatedMinutes: 30)
        let ctx = context(minutes: 30)

        let shortFit = engine.score(barelyUses, among: [barelyUses], context: ctx)
            .factors[.contextualFit] ?? 0
        let fullFit = engine.score(fillsIt, among: [fillsIt], context: ctx)
            .factors[.contextualFit] ?? 0

        #expect(fullFit > shortFit)
    }

    @Test("contextual fit is neutral when the user has not stated a time budget")
    func contextualFitIsZeroWithoutABudget() {
        let task = makeTask(id: "t", estimatedMinutes: 30)

        let score = engine.score(task, among: [task], context: context(minutes: nil))

        #expect(score.factors[.contextualFit] == 0)
    }

    @Test("an unestimated task scores no contextual fit, even inside a stated window")
    func contextualFitIsZeroWithoutAnEstimate() {
        // The other half of `contextualFitIsZeroWithoutABudget`: that one holds the estimate
        // and removes the budget, this one holds the budget and removes the estimate. Both
        // ends of the same guard, so neither can be dropped unnoticed.
        let unestimated = makeTask(id: "unknown", estimatedMinutes: nil)

        let score = engine.score(unestimated, among: [unestimated], context: context(minutes: 30))

        #expect(score.factors[.contextualFit] == 0)
    }

    @Test("inside a stated window, work of known length is preferred to work of unknown length")
    func statingAWindowPrefersAKnownLength() throws {
        // The consequence of the two tests above, and a product decision rather than a fallout
        // — D-025. An unestimated task survives the filter as "might fit" and is then outscored
        // by anything that is known to fit, because the whole point of stating a window is to
        // be given something that fits inside it. NEXT can promise that of the estimated task
        // and cannot promise it of the other.
        //
        // Deliberately confined to a stated window. Today never asks for one, so on the screen
        // that matters most this factor is zero for everything and an unestimated task is not
        // disadvantaged at all.
        let unestimated = makeTask(id: "a-unknown", estimatedMinutes: nil)
        let estimated = makeTask(id: "z-known", estimatedMinutes: 30)

        let outcome = engine.recommend(from: [unestimated, estimated], context: context(minutes: 30))

        // The identifiers are the wrong way round on purpose: with contextual fit removed the
        // two tie on every factor and the tie-break hands it to "a-unknown".
        #expect(try #require(outcome.recommendation).task.id == estimated.id)
    }

    @Test("between two tasks that both fit, the more urgent one still wins")
    func urgencyStillDominatesWithinTheWindow() throws {
        let urgent = makeTask(
            id: "urgent", deadline: .hoursFromReference(2), estimatedMinutes: 10
        )
        let relaxed = makeTask(
            id: "relaxed", deadline: .daysFromReference(6), estimatedMinutes: 15
        )

        let outcome = engine.recommend(from: [relaxed, urgent], context: context(minutes: 15))

        #expect(try #require(outcome.recommendation).task.id == urgent.id)
    }
}
