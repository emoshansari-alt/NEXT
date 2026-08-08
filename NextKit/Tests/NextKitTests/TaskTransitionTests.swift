import Foundation
import Testing

@testable import NextKit

// Task state transitions. Each one is a pure function from a task and an instant to a new
// task, so the whole CAPTURE → DECIDE → START → FINISH → NEXT loop can be exercised without a
// store, a clock or a UI.

@Suite("TaskItem transitions — starting")
struct TaskStartTransitionTests {

    @Test("starting an active task leaves it active and keeps its identity")
    func startingKeepsIdentity() throws {
        let chem = makeTask(id: "chem", title: "Chemistry worksheet")

        let started = try chem.started(at: .testReference)

        #expect(started.id == chem.id)
        #expect(started.createdAt == chem.createdAt)
        #expect(started.status == .active)
    }

    @Test("starting a task the user previously turned down clears the penalty")
    func startingClearsRejections() throws {
        // The user just overrode their own "Not this" by choosing this task. Carrying the
        // penalty forward would suppress the very thing they are working on.
        let chem = makeTask(id: "chem", rejections: [rejection(.needSomethingShorter, hoursAgo: 0.5)])

        let started = try chem.started(at: .testReference)

        #expect(started.rejections.isEmpty)
        #expect(started.latestRejection == nil)
    }

    @Test("a started task is no longer penalised by the ranking engine")
    func startingRestoresRanking() throws {
        let engine = RankingEngine()
        let context = RankingContext(now: .testReference)
        let rejected = makeTask(
            id: "chem",
            deadline: .hoursFromReference(6),
            rejections: [rejection(hoursAgo: 0.1)]
        )
        let rival = makeTask(id: "rival", deadline: .hoursFromReference(6))

        let before = engine.recommend(from: [rejected, rival], context: context)
        let after = engine.recommend(
            from: [try rejected.started(at: .testReference), rival], context: context
        )

        #expect(try #require(before.recommendation).task.id == TaskID("rival"))
        #expect(try #require(after.recommendation).task.id == TaskID("chem"))
    }

    @Test("a completed task cannot be started")
    func startingCompletedIsRefused() {
        let done = makeTask(id: "done", status: .completed)

        #expect(throws: TaskTransitionError.notActive(.completed)) {
            try done.started(at: .testReference)
        }
    }

    @Test("an archived task cannot be started")
    func startingArchivedIsRefused() {
        let filed = makeTask(id: "filed", status: .archived)

        #expect(throws: TaskTransitionError.notActive(.archived)) {
            try filed.started(at: .testReference)
        }
    }
}

@Suite("TaskItem transitions — completing")
struct TaskCompleteTransitionTests {

    @Test("completing an active task marks it completed")
    func completingSetsStatus() throws {
        let chem = makeTask(id: "chem")

        #expect(try chem.completed(at: .testReference).status == .completed)
    }

    @Test("completing keeps everything else about the task intact")
    func completingPreservesContent() throws {
        let chem = makeTask(
            id: "chem",
            title: "Chemistry worksheet",
            deadline: .daysFromReference(1),
            importance: .important,
            estimatedMinutes: 25,
            nextAction: "Do questions 1 to 5."
        )

        let done = try chem.completed(at: .testReference)

        #expect(done.title == chem.title)
        #expect(done.deadline == chem.deadline)
        #expect(done.importance == chem.importance)
        #expect(done.estimatedMinutes == chem.estimatedMinutes)
        #expect(done.nextAction == chem.nextAction)
    }

    @Test("completing an already-completed task is refused")
    func completingTwiceIsRefused() {
        let done = makeTask(id: "done", status: .completed)

        #expect(throws: TaskTransitionError.notActive(.completed)) {
            try done.completed(at: .testReference)
        }
    }

    @Test("completing an archived task is refused")
    func completingArchivedIsRefused() {
        let filed = makeTask(id: "filed", status: .archived)

        #expect(throws: TaskTransitionError.notActive(.archived)) {
            try filed.completed(at: .testReference)
        }
    }

    @Test("a completed task drops out of the recommendation and the next one takes over")
    func completingAdvancesTheLoop() throws {
        let engine = RankingEngine()
        let context = RankingContext(now: .testReference)
        let first = makeTask(id: "first", deadline: .hoursFromReference(2))
        let second = makeTask(id: "second", deadline: .daysFromReference(2))

        let before = engine.recommend(from: [first, second], context: context)
        let after = engine.recommend(
            from: [try first.completed(at: .testReference), second], context: context
        )

        #expect(try #require(before.recommendation).task.id == TaskID("first"))
        #expect(try #require(after.recommendation).task.id == TaskID("second"))
    }

    @Test("completing a prerequisite releases what was waiting on it")
    func completingUnblocksDependents() throws {
        let engine = RankingEngine()
        let context = RankingContext(now: .testReference)
        let research = makeTask(id: "research")
        let write = makeTask(id: "write", prerequisiteIDs: [TaskID("research")])

        let outcome = engine.recommend(
            from: [try research.completed(at: .testReference), write], context: context
        )

        #expect(try #require(outcome.recommendation).task.id == TaskID("write"))
    }
}

@Suite("TaskItem transitions — reopening")
struct TaskReopenTransitionTests {

    @Test("reopening a completed task makes it active again")
    func reopeningCompleted() throws {
        let done = makeTask(id: "done", status: .completed)

        #expect(try done.reopened(at: .testReference).status == .active)
    }

    @Test("reopening an archived task makes it active again")
    func reopeningArchived() throws {
        let filed = makeTask(id: "filed", status: .archived)

        #expect(try filed.reopened(at: .testReference).status == .active)
    }

    @Test("reopening clears stale rejections so the task gets a fair hearing")
    func reopeningClearsRejections() throws {
        let done = makeTask(
            id: "done", status: .completed, rejections: [rejection(hoursAgo: 0.25)]
        )

        #expect(try done.reopened(at: .testReference).rejections.isEmpty)
    }

    @Test("reopening a task that is already active is refused")
    func reopeningActiveIsRefused() {
        let chem = makeTask(id: "chem", status: .active)

        #expect(throws: TaskTransitionError.alreadyActive) {
            try chem.reopened(at: .testReference)
        }
    }
}

@Suite("TaskItem transitions — archiving")
struct TaskArchiveTransitionTests {

    @Test("archiving an active task files it away")
    func archivingActive() throws {
        let chem = makeTask(id: "chem")

        #expect(try chem.archived(at: .testReference).status == .archived)
    }

    @Test("a completed task can also be filed away")
    func archivingCompleted() throws {
        let done = makeTask(id: "done", status: .completed)

        #expect(try done.archived(at: .testReference).status == .archived)
    }

    @Test("archiving something already archived is refused")
    func archivingTwiceIsRefused() {
        let filed = makeTask(id: "filed", status: .archived)

        #expect(throws: TaskTransitionError.alreadyArchived) {
            try filed.archived(at: .testReference)
        }
    }

    @Test("an archived task is never recommended")
    func archivedTaskLeavesTheRunning() throws {
        let engine = RankingEngine()
        let chem = makeTask(id: "chem", deadline: .hoursFromReference(1))

        let outcome = engine.recommend(
            from: [try chem.archived(at: .testReference)],
            context: RankingContext(now: .testReference)
        )

        #expect(outcome == .nothingAvailable(.noActiveTasks))
    }
}

@Suite("TaskItem transitions — recording a rejection")
struct TaskRejectionTransitionTests {

    @Test("a rejection is recorded with the reason and the instant it happened")
    func rejectionIsRecorded() throws {
        let chem = makeTask(id: "chem")

        let rejected = try chem.rejected(.needSomethingShorter, at: .testReference)

        #expect(rejected.rejections.count == 1)
        #expect(rejected.latestRejection?.reason == .needSomethingShorter)
        #expect(rejected.latestRejection?.at == .testReference)
    }

    @Test("the task stays active — rejecting a recommendation is not refusing the work")
    func rejectionDoesNotChangeStatus() throws {
        let chem = makeTask(id: "chem")

        #expect(try chem.rejected(.cantRightNow, at: .testReference).status == .active)
    }

    @Test("rejections accumulate oldest first")
    func rejectionsAccumulate() throws {
        let chem = makeTask(id: "chem")

        let twice = try chem
            .rejected(.cantRightNow, at: .hoursFromReference(-2))
            .rejected(.needLessEffort, at: .testReference)

        #expect(twice.rejections.map(\.reason) == [.cantRightNow, .needLessEffort])
        #expect(twice.latestRejection?.reason == .needLessEffort)
    }

    @Test("a fresh rejection re-arms the penalty in the ranking engine")
    func rejectionPenalisesRanking() throws {
        let engine = RankingEngine()
        let context = RankingContext(now: .testReference)
        let chem = makeTask(id: "chem", deadline: .hoursFromReference(6))
        let rival = makeTask(id: "rival", deadline: .hoursFromReference(6))

        let outcome = engine.recommend(
            from: [try chem.rejected(.cantRightNow, at: .testReference), rival],
            context: context
        )

        #expect(try #require(outcome.recommendation).task.id == TaskID("rival"))
    }

    @Test("a completed task cannot be rejected — it was never on offer")
    func rejectingCompletedIsRefused() {
        let done = makeTask(id: "done", status: .completed)

        #expect(throws: TaskTransitionError.notActive(.completed)) {
            try done.rejected(.cantRightNow, at: .testReference)
        }
    }
}

@Suite("TaskItem transitions — setting the next action")
struct TaskNextActionTransitionTests {

    @Test("setting the next action makes the task startable")
    func nextActionIsStored() throws {
        let chem = makeTask(id: "chem")

        let ready = try chem.withNextAction("Do questions 1 to 5.", at: .testReference)

        #expect(ready.nextAction == "Do questions 1 to 5.")
        #expect(ready.hasConcreteNextAction)
    }

    @Test("surrounding whitespace is trimmed rather than stored")
    func nextActionIsTrimmed() throws {
        let chem = makeTask(id: "chem")

        let ready = try chem.withNextAction("  Open the assignment instructions. \n", at: .testReference)

        #expect(ready.nextAction == "Open the assignment instructions.")
    }

    @Test("replacing an existing next action keeps only the new one")
    func nextActionIsReplaced() throws {
        let chem = makeTask(id: "chem", nextAction: "Read the brief.")

        let ready = try chem.withNextAction("Find three sources.", at: .testReference)

        #expect(ready.nextAction == "Find three sources.")
    }

    @Test("a blank next action is refused rather than stored as a lie")
    func blankNextActionIsRefused() {
        // A whitespace-only action would make the task look startable while leaving the user
        // with nothing to actually do.
        let chem = makeTask(id: "chem")

        #expect(throws: TaskTransitionError.emptyNextAction) {
            try chem.withNextAction("   \n ", at: .testReference)
        }
    }

    @Test("an empty next action is refused")
    func emptyNextActionIsRefused() {
        let chem = makeTask(id: "chem")

        #expect(throws: TaskTransitionError.emptyNextAction) {
            try chem.withNextAction("", at: .testReference)
        }
    }

    @Test("a completed task does not accept a new next action")
    func nextActionOnCompletedIsRefused() {
        let done = makeTask(id: "done", status: .completed)

        #expect(throws: TaskTransitionError.notActive(.completed)) {
            try done.withNextAction("Something.", at: .testReference)
        }
    }
}

@Suite("TaskItem transitions — purity")
struct TaskTransitionPurityTests {

    @Test("no transition mutates the task it was called on")
    func transitionsLeaveTheOriginalAlone() throws {
        let chem = makeTask(id: "chem", title: "Chemistry worksheet")
        let snapshot = chem

        _ = try chem.started(at: .testReference)
        _ = try chem.completed(at: .testReference)
        _ = try chem.archived(at: .testReference)
        _ = try chem.rejected(.cantRightNow, at: .testReference)
        _ = try chem.withNextAction("Do questions 1 to 5.", at: .testReference)

        #expect(chem == snapshot)
    }

    @Test("no transition changes identity or creation time")
    func transitionsPreserveIdentity() throws {
        let chem = makeTask(id: "chem", createdAt: .daysFromReference(-3))

        let results = [
            try chem.started(at: .testReference),
            try chem.completed(at: .testReference),
            try chem.archived(at: .testReference),
            try chem.rejected(.other, at: .testReference),
            try chem.withNextAction("Start.", at: .testReference)
        ]

        #expect(results.allSatisfy { $0.id == chem.id })
        #expect(results.allSatisfy { $0.createdAt == chem.createdAt })
    }

    @Test("the same transition on the same input always gives the same result")
    func transitionsAreDeterministic() throws {
        let chem = makeTask(id: "chem", title: "Chemistry worksheet")

        #expect(
            try chem.rejected(.needLessEffort, at: .testReference)
                == (try chem.rejected(.needLessEffort, at: .testReference))
        )
        #expect(try chem.completed(at: .testReference) == (try chem.completed(at: .testReference)))
    }

    @Test("complete then reopen returns the task to where it started")
    func completeThenReopenRoundTrips() throws {
        let chem = makeTask(id: "chem", title: "Chemistry worksheet", nextAction: "Question 1.")

        let roundTripped = try chem
            .completed(at: .testReference)
            .reopened(at: .hoursFromReference(1))

        #expect(roundTripped == chem)
    }
}

@Suite("TaskItem transitions — refusals")
struct TaskTransitionRefusalTests {

    @Test("a refusal names the state that caused it, so the caller can react precisely")
    func refusalCarriesTheState() {
        let filed = makeTask(id: "filed", status: .archived)
        let done = makeTask(id: "done", status: .completed)

        #expect(throws: TaskTransitionError.notActive(.archived)) {
            try filed.completed(at: .testReference)
        }
        #expect(throws: TaskTransitionError.notActive(.completed)) {
            try done.completed(at: .testReference)
        }
    }

    @Test("a caller that wants a no-op can have one")
    func refusalsCanBeIgnored() {
        // Throwing is the loud default; `try?` buys idempotence where a surface genuinely
        // wants it. The reverse — recovering a reason from a silent no-op — is impossible.
        let done = makeTask(id: "done", status: .completed)

        #expect((try? done.completed(at: .testReference)) == nil)
    }

    @Test("refusal descriptions stay factual and never address the user")
    func refusalsAreNotUserFacing() {
        // These are developer diagnostics. P5 forbids productivity morality anywhere it could
        // reach a screen, so nothing here may read as a judgement.
        let banned = [
            "you", "your", "fail", "behind", "again", "still", "lazy", "streak", "should"
        ]

        for error in TaskTransitionError.allCases {
            let text = String(describing: error).lowercased()
            for word in banned {
                #expect(!text.contains(word), "\(error) contains banned language: \(word)")
            }
        }
    }
}
