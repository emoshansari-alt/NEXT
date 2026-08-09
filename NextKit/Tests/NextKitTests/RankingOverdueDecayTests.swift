import Foundation
import Testing

@testable import NextKit

/// What a deadline still means once it has passed.
///
/// The open question from Session 1, left deliberately unanswered at the time: overdue
/// contributed a flat full weight with no decay, so a task three months late scored exactly what
/// it scored an hour after its deadline — and pinned to the top of the screen permanently.
///
/// That is a defect against two invariants at once. **P4** says a missed day triggers
/// recalculation, never punishment, and a screen that shows the same unachievable thing every
/// morning for a term is punishment however neutrally it is worded. **P5** forbids productivity
/// morality, and there is no stronger way to say "you failed at this" than to refuse to talk
/// about anything else. It also breaks the product's own promise: an app whose single
/// recommendation never changes has stopped recommending.
///
/// The answer is that lateness decays but never disappears, because the work is still
/// outstanding — see `DECISIONS.md` D-020.
@Suite("Ranking — a deadline that has already passed")
struct RankingOverdueDecayTests {

    private let engine = RankingEngine()
    private let weights = ScoringWeights.default

    private func score(_ task: TaskItem, at now: Date = .testReference) -> Double {
        engine.score(task, among: [task], context: RankingContext(now: now)).total
    }

    @Test("a deadline that has just passed is as urgent as anything gets")
    func freshlyOverdueIsMaximal() {
        // The moment of the deadline itself, where the decay has not travelled at all. Nothing
        // about the existing behaviour changes here, and that matters: the hours either side of
        // a deadline are exactly when acting still nearly meets it.
        let due = makeTask(id: "late", deadline: .testReference)

        let breakdown = engine.score(
            due, among: [due], context: RankingContext(now: .testReference)
        )

        #expect(breakdown.factors[.deadlineUrgency] == weights.deadlineUrgency)
        #expect(breakdown.factors[.overdueRelevance] == weights.overdueRelevance)
    }

    @Test("an hour late is still, to any useful precision, as urgent as it gets")
    func anHourLateIsEffectivelyUnchanged() throws {
        // The decay is measured in days, so it must be invisible over an hour. A curve steep
        // enough to matter overnight would reorder the screen while the user slept.
        let justLate = makeTask(id: "late", deadline: .hoursFromReference(-1))

        let breakdown = engine.score(
            justLate, among: [justLate], context: RankingContext(now: .testReference)
        )
        // `try #require`, not `try? #require ... ?? 0`. The earlier form let a missing factor
        // score zero and still read as a meaningful assertion — it would have failed, but for
        // the wrong reason and with a misleading message. A factor is guaranteed present
        // (`ScoreBreakdown.factors`), so its absence is a broken invariant, not a low value.
        let urgency = try #require(breakdown.factors[.deadlineUrgency])

        #expect(urgency > weights.deadlineUrgency * 0.99)
    }

    @Test("lateness stops growing louder the longer it goes on")
    func longOverdueScoresLessThanFreshlyOverdue() {
        let justLate = makeTask(id: "fresh", deadline: .hoursFromReference(-2))
        let ancient = makeTask(id: "ancient", deadline: .daysFromReference(-90))

        #expect(score(ancient) < score(justLate))
    }

    @Test("a task due tomorrow outranks one that has been late for months")
    func nearFutureWorkOvertakesAncientLateness() {
        // The behaviour the user actually notices. Until this decayed, an abandoned task from
        // last term sat on the Today screen in front of work that was still achievable.
        let ancient = makeTask(id: "ancient", deadline: .daysFromReference(-90))
        let tomorrow = makeTask(id: "tomorrow", deadline: .daysFromReference(1))

        let outcome = engine.recommend(
            from: [ancient, tomorrow], context: RankingContext(now: .testReference)
        )

        #expect(outcome.recommendation?.task.id == TaskID("tomorrow"))
    }

    @Test("but late work never becomes invisible")
    func latenessDecaysToAFloorRatherThanToNothing() {
        // It is still outstanding, and a task that silently sank below everything would be the
        // app quietly deciding on the user's behalf that it no longer matters.
        let ancient = makeTask(id: "ancient", deadline: .daysFromReference(-365))
        let undated = makeTask(id: "someday")

        #expect(score(ancient) > score(undated))

        let outcome = engine.recommend(
            from: [ancient, undated], context: RankingContext(now: .testReference)
        )
        #expect(outcome.recommendation?.task.id == TaskID("ancient"))
    }

    @Test("the decay bottoms out rather than running away")
    func decayIsBoundedBelow() {
        // Two tasks, both far past the horizon. Neither should keep sinking relative to the
        // other, or the oldest item in a store would drift toward zero forever.
        let old = makeTask(id: "old", deadline: .daysFromReference(-60))
        let older = makeTask(id: "older", deadline: .daysFromReference(-600))

        #expect(score(old) == score(older))
    }

    @Test("decay is monotonic across the horizon")
    func moreOverdueIsNeverWorthMore() {
        // Swept rather than sampled: a curve that dipped and recovered would still satisfy any
        // pair of endpoints, and would make the recommendation jump about for no visible reason.
        let horizonDays = weights.overdueHorizon / (24 * 3600)
        var previous = Double.infinity

        for step in 0...20 {
            let daysLate = horizonDays * Double(step) / 20
            let task = makeTask(id: "t\(step)", deadline: .daysFromReference(-daysLate))
            let current = score(task)

            #expect(current <= previous, "score rose at \(daysLate) days late")
            previous = current
        }
    }

    @Test("a task with no deadline is untouched by any of this")
    func undatedWorkIsUnaffected() {
        let undated = makeTask(id: "someday")

        let breakdown = engine.score(
            undated, among: [undated], context: RankingContext(now: .testReference)
        )

        #expect(breakdown.factors[.deadlineUrgency] == 0)
        #expect(breakdown.factors[.overdueRelevance] == 0)
    }

    @Test("nothing about being late is phrased as a judgement")
    func latenessIsNeverWordedAsFailure() {
        // P5. The engine's own words are swept elsewhere; this pins the specific case, because
        // "overdue" is exactly where a scolding sentence would feel most natural to write.
        let ancient = makeTask(id: "ancient", title: "History essay", deadline: .daysFromReference(-90))

        let outcome = engine.recommend(
            from: [ancient], context: RankingContext(now: .testReference)
        )
        let sentence = try? #require(outcome.recommendation?.explanation.sentence).lowercased()

        // Note what is *not* forbidden: "overdue" itself. "Overdue by 3 months." is a fact the
        // user needs, and refusing to say it would be a different failure — an app being coy
        // about a deadline to spare feelings is an app that cannot be trusted about deadlines.
        // What is forbidden is judgement layered on top of the fact.
        for phrase in ["should have", "failed", "you didn't", "finally", "behind", "!"] {
            #expect(sentence?.contains(phrase) != true, "the explanation says \"\(phrase)\"")
        }
    }
}
