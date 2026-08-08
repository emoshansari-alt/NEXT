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
        let rejected = makeTask(
            id: "rejected", deadline: deadline, rejections: [rejection(hoursAgo: 0)]
        )
        let alternative = makeTask(id: "alternative", deadline: deadline)

        let outcome = engine.recommend(from: [rejected, alternative], context: context)

        #expect(try #require(outcome.recommendation).task.id == alternative.id)
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
