import Foundation
import Testing

@testable import NextKit

// These tests define what "the right task" means. They are the specification of the
// deterministic engine, and they are the reason a cloud model is never allowed to make this
// decision (PRODUCT_SPEC.md §5).
//
// Each test isolates a single ranking factor by holding every other field equal, so a failure
// names the factor that broke.

@Suite("RankingEngine — deadline urgency")
struct DeadlineUrgencyTests {

    let engine = RankingEngine()
    let context = RankingContext(now: .testReference)

    @Test("prefers the task whose deadline is sooner")
    func soonerDeadlineWins() throws {
        let tomorrow = makeTask(id: "soon", deadline: .daysFromReference(1))
        let nextWeek = makeTask(id: "later", deadline: .daysFromReference(5))

        let outcome = engine.recommend(from: [nextWeek, tomorrow], context: context)

        #expect(try #require(outcome.recommendation).task.id == tomorrow.id)
    }

    @Test("an overdue task outranks one that is merely due soon")
    func overdueOutranksUpcoming() throws {
        let overdue = makeTask(id: "overdue", deadline: .daysFromReference(-1))
        let upcoming = makeTask(id: "upcoming", deadline: .daysFromReference(3))

        let outcome = engine.recommend(from: [upcoming, overdue], context: context)

        #expect(try #require(outcome.recommendation).task.id == overdue.id)
    }

    @Test("a task with a deadline outranks one with no deadline")
    func deadlinedOutranksUndated() throws {
        let dated = makeTask(id: "dated", deadline: .daysFromReference(5))
        let undated = makeTask(id: "undated", deadline: nil)

        let outcome = engine.recommend(from: [undated, dated], context: context)

        #expect(try #require(outcome.recommendation).task.id == dated.id)
    }

    @Test("a deadline beyond the urgency horizon contributes no urgency")
    func distantDeadlineContributesNoUrgency() {
        let distant = makeTask(id: "distant", deadline: .daysFromReference(60))

        let score = engine.score(distant, among: [distant], context: context)

        #expect(score.factors[.deadlineUrgency] == 0)
    }

    @Test("a task due right now scores maximum urgency")
    func dueNowScoresMaximumUrgency() {
        let dueNow = makeTask(id: "now", deadline: .testReference)
        let weights = ScoringWeights.default

        let score = engine.score(dueNow, among: [dueNow], context: context)

        #expect(score.factors[.deadlineUrgency] == weights.deadlineUrgency)
    }
}

@Suite("RankingEngine — importance")
struct ImportanceTests {

    let engine = RankingEngine()
    let context = RankingContext(now: .testReference)

    @Test("an important task outranks a normal one with the same deadline")
    func importantOutranksNormalAtEqualDeadline() throws {
        let deadline = Date.daysFromReference(2)
        let normal = makeTask(id: "normal", deadline: deadline, importance: .normal)
        let important = makeTask(id: "important", deadline: deadline, importance: .important)

        let outcome = engine.recommend(from: [normal, important], context: context)

        #expect(try #require(outcome.recommendation).task.id == important.id)
    }

    @Test("importance does not override a much closer deadline")
    func importanceDoesNotOverwhelmUrgency() throws {
        // An important essay due in a week should not beat a normal worksheet due in an hour.
        // Urgency is the dominant factor; importance breaks near-ties.
        let importantButDistant = makeTask(
            id: "essay", deadline: .daysFromReference(7), importance: .important
        )
        let normalButImminent = makeTask(
            id: "worksheet", deadline: .hoursFromReference(1), importance: .normal
        )

        let outcome = engine.recommend(
            from: [importantButDistant, normalButImminent], context: context
        )

        #expect(try #require(outcome.recommendation).task.id == normalButImminent.id)
    }
}

@Suite("RankingEngine — determinism")
struct RankingDeterminismTests {

    let engine = RankingEngine()
    let context = RankingContext(now: .testReference)

    @Test("identical scores break the tie by earliest creation, not by array order")
    func tiesBreakByCreationDate() throws {
        let older = makeTask(id: "older", createdAt: .daysFromReference(-3))
        let newer = makeTask(id: "newer", createdAt: .daysFromReference(-1))

        let oneOrder = engine.recommend(from: [newer, older], context: context)
        let otherOrder = engine.recommend(from: [older, newer], context: context)

        #expect(try #require(oneOrder.recommendation).task.id == older.id)
        #expect(try #require(otherOrder.recommendation).task.id == older.id)
    }

    @Test("the same input always produces the same recommendation")
    func rankingIsReproducible() {
        let tasks = [
            makeTask(id: "a", deadline: .daysFromReference(2)),
            makeTask(id: "b", deadline: .daysFromReference(1), importance: .important),
            makeTask(id: "c", deadline: nil),
            makeTask(id: "d", deadline: .daysFromReference(-2))
        ]

        let results = (0..<10).map { _ in
            engine.recommend(from: tasks, context: context).recommendation?.task.id
        }

        #expect(Set(results).count == 1)
    }

    @Test("every factor is present in a score breakdown, even at zero")
    func scoreBreakdownIsComplete() {
        // "Why this?" is generated from the breakdown, so a missing factor is a missing
        // explanation. Absent must be spelled zero, never omitted.
        let task = makeTask(id: "t", deadline: .daysFromReference(1))

        let score = engine.score(task, among: [task], context: context)

        for factor in RankingFactor.allCases {
            #expect(score.factors[factor] != nil, "factor \(factor) missing from breakdown")
        }
    }

    @Test("the total equals the sum of the factors")
    func totalIsSumOfFactors() {
        let task = makeTask(id: "t", deadline: .daysFromReference(1), importance: .important)

        let score = engine.score(task, among: [task], context: context)

        let sum = score.factors.values.reduce(0, +)
        #expect(abs(score.total - sum) < 0.000_001)
    }
}
