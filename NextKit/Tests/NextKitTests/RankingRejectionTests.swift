import Foundation
import Testing

@testable import NextKit

// "Not this" is a first-class interaction, not an undo. The engine must respect it without
// ever leaving the user staring at a blank screen — PRODUCT_SPEC.md §4.3.

@Suite("RankingEngine — rejection")
struct RankingRejectionTests {

    let engine = RankingEngine()
    let context = RankingContext(now: .testReference)

    @Test("a just-rejected task loses to an otherwise identical alternative")
    func freshRejectionDemotesTask() throws {
        let deadline = Date.daysFromReference(1)
        // The identifiers are load-bearing, and this is the second version of this test.
        //
        // The first named them "rejected" and "alternative", which made it incapable of
        // failing: with the penalty removed the two tasks tie on every factor, the tie-break
        // falls through to the identifier, and "alternative" < "rejected" wins anyway — the
        // expected answer for a reason that has nothing to do with rejection. Naming the
        // rejected task so it would win the tie-break is what makes the penalty the only thing
        // that can produce this result.
        let rejected = makeTask(
            id: "a-rejected", deadline: deadline, rejections: [rejection(hoursAgo: 0)]
        )
        let alternative = makeTask(id: "z-alternative", deadline: deadline)

        let outcome = engine.recommend(from: [rejected, alternative], context: context)

        #expect(try #require(outcome.recommendation).task.id == alternative.id)
    }

    @Test("rejecting the task the engine just recommended gets a different answer")
    func theLoopClosesOnItself() throws {
        // The loop `PRODUCT_SPEC.md` §4.3 and `TESTING.md` describe, run as a loop rather than
        // asserted as two separate facts. The rejected task is whichever one the engine picked,
        // taken from its own first answer — not named in the fixture — so this cannot pass by
        // agreeing with a guess about which task would win.
        let deadline = Date.daysFromReference(1)
        let tasks = [
            makeTask(id: "chem", deadline: deadline),
            makeTask(id: "essay", deadline: deadline)
        ]

        let first = try #require(
            engine.recommend(from: tasks, context: context).recommendation
        ).task

        // Rejected through the real transition, so the test exercises the path the button
        // takes rather than a hand-built `Rejection` the app never constructs.
        var afterRejection: [TaskItem] = []
        for task in tasks {
            afterRejection.append(
                task.id == first.id ? try task.rejected(.cantRightNow, at: .testReference) : task
            )
        }

        let second = try #require(
            engine.recommend(from: afterRejection, context: context).recommendation
        )

        #expect(second.task.id != first.id)
        #expect(second.wasRecentlyRejected == false)
    }

    @Test("the rejection penalty decays and expires after the cooldown")
    func rejectionExpiresAfterCooldown() throws {
        let cooldownHours = ScoringWeights.default.rejectionCooldown / 3600
        // Rejected longer ago than the cooldown, so the penalty should be entirely gone.
        let staleRejection = makeTask(
            id: "stale",
            deadline: .daysFromReference(1),
            rejections: [rejection(hoursAgo: cooldownHours + 1)]
        )

        let score = engine.score(staleRejection, among: [staleRejection], context: context)

        #expect(score.factors[.rejectionPenalty] == 0)
    }

    @Test("a more recent rejection is penalised harder than an older one")
    func penaltyDecaysWithTime() {
        let recent = makeTask(id: "recent", rejections: [rejection(hoursAgo: 0.5)])
        let older = makeTask(id: "older", rejections: [rejection(hoursAgo: 3)])

        let recentPenalty = engine.score(recent, among: [recent], context: context)
            .factors[.rejectionPenalty] ?? 0
        let olderPenalty = engine.score(older, among: [older], context: context)
            .factors[.rejectionPenalty] ?? 0

        // Penalties are stored negative, so "harder" means more negative.
        #expect(recentPenalty < olderPenalty)
        #expect(recentPenalty < 0)
    }

    @Test("rejecting again re-arms the penalty from the newest rejection")
    func newestRejectionDrivesThePenalty() {
        let onceLongAgo = makeTask(id: "a", rejections: [rejection(hoursAgo: 3.5)])
        let rejectedAgainJustNow = makeTask(
            id: "b", rejections: [rejection(hoursAgo: 3.5), rejection(hoursAgo: 0)]
        )

        let stalePenalty = engine.score(onceLongAgo, among: [onceLongAgo], context: context)
            .factors[.rejectionPenalty] ?? 0
        let freshPenalty = engine
            .score(rejectedAgainJustNow, among: [rejectedAgainJustNow], context: context)
            .factors[.rejectionPenalty] ?? 0

        #expect(freshPenalty < stalePenalty)
    }

    @Test("the penalty follows the newest rejection, never the number of them")
    func penaltyIsRecencyNotTally() {
        // `newestRejectionDrivesThePenalty` above varies count *and* recency together, so it
        // would still pass if someone made the penalty scale with `activeRejections.count`.
        // This holds recency fixed and varies only the tally.
        //
        // Recency-only is the deliberate rule, and it is the one P5 requires. A tally would
        // mean that saying "not this" four times over a term costs a task more than saying it
        // once an hour ago, so a task the user has repeatedly and legitimately deferred would
        // sink permanently — which is D-020's defect wearing a different hat.
        // An hour ago rather than this instant, deliberately: at zero elapsed the decay returns
        // 1 before any arithmetic runs, so a tally-based penalty would clamp to the same 1 and
        // the test could not tell the two apart. Partway through the cooldown it can.
        let onceRejected = makeTask(id: "once", rejections: [rejection(hoursAgo: 1)])
        let rejectedRepeatedly = makeTask(
            id: "many",
            rejections: [rejection(hoursAgo: 3), rejection(hoursAgo: 2), rejection(hoursAgo: 1)]
        )

        let oncePenalty = engine.score(onceRejected, among: [onceRejected], context: context)
            .factors[.rejectionPenalty]
        let manyPenalty = engine
            .score(rejectedRepeatedly, among: [rejectedRepeatedly], context: context)
            .factors[.rejectionPenalty]

        #expect(oncePenalty == manyPenalty)
    }

    @Test("a rejected task is still returned when it is the only thing there is")
    func soleRejectedTaskIsStillRecommended() throws {
        // Recommending nothing would be worse than recommending the rejected task. The
        // penalty is finite precisely so this can happen.
        let onlyTask = makeTask(
            id: "only", deadline: .daysFromReference(1), rejections: [rejection(hoursAgo: 0)]
        )

        let outcome = engine.recommend(from: [onlyTask], context: context)

        #expect(try #require(outcome.recommendation).task.id == onlyTask.id)
    }

    @Test("the recommendation says when the only option was one the user already rejected")
    func soleRejectedTaskIsFlagged() throws {
        let onlyTask = makeTask(id: "only", rejections: [rejection(hoursAgo: 0)])

        let outcome = engine.recommend(from: [onlyTask], context: context)

        // The UI needs to be able to say "this is the one you passed on, but it's all
        // that's left" rather than silently re-serving it as if nothing happened.
        #expect(try #require(outcome.recommendation).wasRecentlyRejected)
    }

    @Test("a rejected task that outscores a live alternative anyway is still flagged")
    func aRejectedTaskThatWinsOnMeritIsFlagged() throws {
        // `soleRejectedTaskIsFlagged` proves the flag when there was nothing else to offer.
        // This is the case the engine can actually reach with a full task list, and the one the
        // flag exists for: the penalty is finite (60 against a positive maximum of 112), so a
        // rejected task that is genuinely the most pressing thing comes back while alternatives
        // are still on the list. The screen must say so rather than re-serving it silently.
        //
        // Arithmetic, so this cannot pass by accident: the rejected task is an hour overdue and
        // important — very nearly 40 + 25 + 15, less the full 60 — leaving roughly 20 against
        // the undated alternative's zero.
        let rejected = makeTask(
            id: "overdue-and-important",
            deadline: .hoursFromReference(-1),
            importance: .important,
            rejections: [rejection(hoursAgo: 0)]
        )
        let alternative = makeTask(id: "someday")

        let outcome = engine.recommend(from: [rejected, alternative], context: context)
        let recommendation = try #require(outcome.recommendation)

        #expect(recommendation.task.id == rejected.id)
        #expect(recommendation.wasRecentlyRejected)
    }

    @Test("a task never rejected is not flagged as rejected")
    func unrejectedTaskIsNotFlagged() throws {
        let task = makeTask(id: "clean")

        let outcome = engine.recommend(from: [task], context: context)

        #expect(try #require(outcome.recommendation).wasRecentlyRejected == false)
    }

    @Test("a rejection older than the cooldown does not flag the recommendation")
    func staleRejectionDoesNotFlag() throws {
        let cooldownHours = ScoringWeights.default.rejectionCooldown / 3600
        let task = makeTask(id: "t", rejections: [rejection(hoursAgo: cooldownHours + 1)])

        let outcome = engine.recommend(from: [task], context: context)

        #expect(try #require(outcome.recommendation).wasRecentlyRejected == false)
    }
}
