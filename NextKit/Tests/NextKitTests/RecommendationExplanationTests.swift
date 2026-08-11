import Foundation
import Testing

@testable import NextKit

// "Why this?" must always be answerable, offline, with no model involved — the recommendation
// is never presented as an unknowable oracle (PRODUCT_SPEC.md §4.4). The explanation is derived
// from the same ScoreBreakdown that produced the ranking, so it can never disagree with it.

@Suite("Recommendation — why this?")
struct RecommendationExplanationTests {

    let engine = RankingEngine()

    private func context(minutes: Int? = nil) -> RankingContext {
        RankingContext(now: .testReference, availableMinutes: minutes)
    }

    private func explanation(
        for tasks: [TaskItem],
        availableMinutes: Int? = nil
    ) throws -> ExplanationReason {
        let outcome = engine.recommend(
            from: tasks, context: context(minutes: availableMinutes)
        )
        return try #require(outcome.recommendation).explanation
    }

    @Test("an overdue task is explained as overdue, not merely urgent")
    func overdueIsExplainedAsOverdue() throws {
        // Urgency outweighs overdue numerically, but "Overdue by 2 days" is the honest and
        // more useful sentence, so overdue takes precedence in the explanation.
        let task = makeTask(id: "t", deadline: .daysFromReference(-2))

        let reason = try explanation(for: [task])

        #expect(reason == .overdue(by: 2 * 24 * 3600))
    }

    @Test("an upcoming deadline is explained by how long is left")
    func upcomingDeadlineIsExplained() throws {
        let task = makeTask(id: "t", deadline: .hoursFromReference(3))

        let reason = try explanation(for: [task])

        #expect(reason == .dueSoon(within: 3 * 3600))
    }

    @Test("a task that unblocks other work is explained by what it unblocks")
    func unlockingIsExplained() throws {
        let tasks = [
            makeTask(id: "gate"),
            makeTask(id: "d1", prerequisiteIDs: [TaskID("gate")]),
            makeTask(id: "d2", prerequisiteIDs: [TaskID("gate")])
        ]

        let reason = try explanation(for: tasks)

        #expect(reason == .unlocksOtherWork(count: 2))
    }

    @Test("an undated important task is explained by its importance")
    func importanceIsExplained() throws {
        let task = makeTask(id: "t", importance: .important)

        let reason = try explanation(for: [task])

        #expect(reason == .markedImportant)
    }

    @Test("when the user gave a time budget, the fit explains the choice")
    func timeFitIsExplained() throws {
        let task = makeTask(id: "t", estimatedMinutes: 15)

        let reason = try explanation(for: [task], availableMinutes: 15)

        #expect(reason == .fitsTheTimeYouHave(minutes: 15))
    }

    @Test("an undated task with a known first step is explained by that")
    func startabilityIsExplained() throws {
        let task = makeTask(id: "t", nextAction: "Open the assignment instructions.")

        let reason = try explanation(for: [task])

        #expect(reason == .hasAClearFirstStep)
    }

    @Test("a task with nothing notable about it still gets an honest explanation")
    func unremarkableTaskStillExplained() throws {
        // A bare task scores zero on every factor. Saying nothing would leave the UI with a
        // blank "Why this?", so the engine states the plain truth instead.
        let task = makeTask(id: "t")

        let reason = try explanation(for: [task])

        #expect(reason == .nothingElsePending)
    }
}

@Suite("ExplanationReason — sentences")
struct ExplanationSentenceTests {

    @Test("renders a deterministic English sentence for every reason")
    func everyReasonHasASentence() {
        let cases: [(ExplanationReason, String)] = [
            (.overdue(by: 3600), "Overdue by 1 hour."),
            (.overdue(by: 2 * 24 * 3600), "Overdue by 2 days."),
            (.dueSoon(within: 45 * 60), "Due in 45 minutes."),
            (.dueSoon(within: 3 * 3600), "Due in 3 hours."),
            (.dueSoon(within: 24 * 3600), "Due in 1 day."),
            (.unlocksOtherWork(count: 1), "Finishing this unblocks 1 other task."),
            (.unlocksOtherWork(count: 3), "Finishing this unblocks 3 other tasks."),
            (.markedImportant, "You marked this important."),
            (.fitsTheTimeYouHave(minutes: 15), "Fits the 15 minutes you have."),
            (.hasAClearFirstStep, "Nothing to decide before you start."),
            (.nothingElsePending, "Nothing else is more pressing right now.")
        ]

        for (reason, expected) in cases {
            #expect(reason.sentence == expected, "wrong sentence for \(reason)")
        }
    }

    @Test("no sentence shames the user")
    func sentencesAreNeverJudgemental() {
        // P5: no productivity morality. This is a cheap guard against a well-meaning future
        // edit reintroducing the tone the product explicitly rejects.
        let banned = ["failed", "behind", "should have", "streak", "again", "still haven't"]
        let reasons: [ExplanationReason] = [
            .overdue(by: 5 * 24 * 3600),
            .dueSoon(within: 600),
            .unlocksOtherWork(count: 2),
            .markedImportant,
            .fitsTheTimeYouHave(minutes: 30),
            .hasAClearFirstStep,
            .nothingElsePending
        ]

        for reason in reasons {
            let sentence = reason.sentence.lowercased()
            for word in banned {
                #expect(!sentence.contains(word), "'\(word)' appears in: \(reason.sentence)")
            }
        }
    }
}

@Suite("Recommendation — deadline feasibility")
struct DeadlineFeasibilityTests {

    let engine = RankingEngine()
    let context = RankingContext(now: .testReference)

    private func feasibility(_ task: TaskItem) throws -> DeadlineFeasibility {
        let outcome = engine.recommend(from: [task], context: context)
        return try #require(outcome.recommendation).deadlineFeasibility
    }

    @Test("an undated task has no feasibility question to answer")
    func undatedIsNoDeadline() throws {
        let result = try feasibility(makeTask(id: "t", estimatedMinutes: 30))

        #expect(result == .noDeadline)
    }

    @Test("a dated task with no estimate cannot be judged")
    func missingEstimateIsUnknown() throws {
        let result = try feasibility(makeTask(id: "t", deadline: .daysFromReference(1)))

        #expect(result == .unknownDuration)
    }

    @Test("a task needing more time than remains is unreachable")
    func notEnoughTimeIsUnreachable() throws {
        // This is precisely the trigger for Minimum Win (PRODUCT_SPEC.md §4.12).
        let task = makeTask(
            id: "t", deadline: .hoursFromReference(1), estimatedMinutes: 180
        )

        let result = try feasibility(task)

        #expect(result == .unreachable)
    }

    @Test("an overdue task is past its deadline rather than merely unreachable")
    func overdueIsPassed() throws {
        // These were one state until D-030. They are different facts and the card says different
        // things about them: `unreachable` is a window too small to finish in, `passed` is no
        // window at all.
        let task = makeTask(
            id: "t", deadline: .hoursFromReference(-1), estimatedMinutes: 30
        )

        let result = try feasibility(task)

        #expect(result == .passed)
        #expect(result.suggestsMinimumWin, "something smaller is still worth offering")
        #expect(result.deadlineHasPassed)
    }

    @Test("a deadline less than a minute away is still ahead, not passed")
    func aSubMinuteDeadlineIsStillAhead() throws {
        // The boundary defect D-030 found. `MinimumWinPlanner` works in whole minutes, so forty
        // seconds truncates to zero — and for a while that truncation decided which state the
        // user was shown. Feasibility is measured in seconds and is not fooled.
        let task = makeTask(
            id: "t", deadline: .secondsFromReference(40), estimatedMinutes: 30
        )

        let result = try feasibility(task)

        #expect(result == .unreachable)
        #expect(result.deadlineHasPassed == false)
    }

    @Test("the deadline exactly reached counts as passed")
    func theExactBoundaryIsPassed() throws {
        // A zero-length window cannot contain work, so there is nothing for "still ahead" to
        // mean here.
        let task = makeTask(
            id: "t", deadline: .secondsFromReference(0), estimatedMinutes: 30
        )

        #expect(try feasibility(task) == .passed)
    }

    @Test("a task that only just fits is tight")
    func barelyFittingIsTight() throws {
        let task = makeTask(
            id: "t", deadline: .hoursFromReference(2), estimatedMinutes: 90
        )

        let result = try feasibility(task)

        #expect(result == .tight)
    }

    @Test("a task with plenty of room is comfortable")
    func plentyOfRoomIsComfortable() throws {
        let task = makeTask(
            id: "t", deadline: .daysFromReference(5), estimatedMinutes: 30
        )

        let result = try feasibility(task)

        #expect(result == .comfortable)
    }
}
