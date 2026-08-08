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

    @Test("starting a task the user previously turned down supersedes the penalty")
    func startingSupersedesRejections() throws {
        // The user just overrode their own "Not this" by choosing this task. Carrying the
        // penalty forward would suppress the very thing they are working on.
        let chem = makeTask(id: "chem", rejections: [rejection(.needSomethingShorter, hoursAgo: 0.5)])

        let started = try chem.started(at: .testReference)

        #expect(started.rejectionsSupersededAt == .testReference)
        #expect(started.activeRejections.isEmpty)
        #expect(started.latestActiveRejection == nil)
    }

    @Test("starting keeps the rejection record itself — the history is product data")
    func startingKeepsRejectionHistory() throws {
        // The penalty is suppressed by a watermark, never by deleting evidence. Rejection rate
        // is the most valuable signal there is for tuning the engine (PRODUCT_SPEC.md §14), and
        // it can only be measured from records that still exist.
        let chem = makeTask(
            id: "chem",
            rejections: [rejection(.cantRightNow, hoursAgo: 3), rejection(.needLessEffort, hoursAgo: 0.5)]
        )

        let started = try chem.started(at: .testReference)

        #expect(started.rejections == chem.rejections)
        #expect(started.latestRejection?.reason == .needLessEffort)
    }

    @Test("a rejection recorded after the start still counts")
    func rejectionAfterStartingStillCounts() throws {
        // The watermark supersedes the past, not the future. A user who starts something, stops,
        // and then turns it down an hour later has said something new.
        let chem = makeTask(id: "chem", rejections: [rejection(hoursAgo: 3)])

        let restarted = try chem
            .started(at: .testReference)
            .rejected(.needSomethingShorter, at: .hoursFromReference(1))

        #expect(restarted.rejections.count == 2)
        #expect(restarted.activeRejections.count == 1)
        #expect(restarted.latestActiveRejection?.reason == .needSomethingShorter)
    }

    @Test("starting records when it happened")
    func startingRecordsTheInstant() throws {
        let chem = makeTask(id: "chem", createdAt: .daysFromReference(-2))

        let started = try chem.started(at: .testReference)

        #expect(started.updatedAt == .testReference)
        #expect(started.completedAt == nil)
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
            nextAction: "Do questions 1 to 5.",
            prerequisiteIDs: [TaskID("reading")],
            parentID: TaskID("coursework"),
            rejections: [rejection(.cantRightNow, hoursAgo: 4), rejection(.needLessEffort, hoursAgo: 1)]
        )

        let done = try chem.completed(at: .testReference)

        #expect(done.title == chem.title)
        #expect(done.deadline == chem.deadline)
        #expect(done.importance == chem.importance)
        #expect(done.estimatedMinutes == chem.estimatedMinutes)
        #expect(done.nextAction == chem.nextAction)
        #expect(done.prerequisiteIDs == chem.prerequisiteIDs)
        #expect(done.parentID == chem.parentID)
        #expect(done.rejections == chem.rejections)
    }

    @Test("completing records when it happened")
    func completingRecordsTheInstant() throws {
        // `completed(at:)` reads at every call site as if it records a completion instant.
        // It has to actually do that: the Completed section orders by it and daily replanning
        // needs to know which day the work landed on.
        let chem = makeTask(id: "chem", createdAt: .daysFromReference(-1))

        let done = try chem.completed(at: .hoursFromReference(2))

        #expect(done.completedAt == .hoursFromReference(2))
        #expect(done.updatedAt == .hoursFromReference(2))
    }

    @Test("an untouched task was last changed when it was created")
    func untouchedTaskUpdatedAtMatchesCreation() {
        let chem = makeTask(id: "chem", createdAt: .daysFromReference(-4))

        #expect(chem.updatedAt == chem.createdAt)
        #expect(chem.completedAt == nil)
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

    @Test("reopening supersedes stale rejections so the task gets a fair hearing")
    func reopeningSupersedesRejections() throws {
        let done = makeTask(
            id: "done", status: .completed, rejections: [rejection(hoursAgo: 0.25)]
        )

        let reopened = try done.reopened(at: .testReference)

        #expect(reopened.activeRejections.isEmpty)
        #expect(reopened.rejectionsSupersededAt == .testReference)
    }

    @Test("reopening keeps the rejection record itself")
    func reopeningKeepsRejectionHistory() throws {
        let done = makeTask(
            id: "done", status: .completed, rejections: [rejection(hoursAgo: 0.25)]
        )

        #expect(try done.reopened(at: .testReference).rejections == done.rejections)
    }

    @Test("reopening clears the completion instant, because the work is not finished")
    func reopeningClearsCompletion() throws {
        let chem = makeTask(id: "chem")

        let reopened = try chem
            .completed(at: .testReference)
            .reopened(at: .hoursFromReference(1))

        #expect(reopened.completedAt == nil)
        #expect(reopened.updatedAt == .hoursFromReference(1))
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

    @Test("archiving keeps everything else about the task intact")
    func archivingPreservesContent() throws {
        let chem = makeTask(
            id: "chem",
            title: "Chemistry worksheet",
            deadline: .daysFromReference(1),
            importance: .important,
            estimatedMinutes: 25,
            nextAction: "Do questions 1 to 5.",
            prerequisiteIDs: [TaskID("reading")],
            parentID: TaskID("coursework"),
            rejections: [rejection(.cantRightNow, hoursAgo: 4), rejection(.needLessEffort, hoursAgo: 1)]
        )

        let filed = try chem.archived(at: .testReference)

        #expect(filed.title == chem.title)
        #expect(filed.deadline == chem.deadline)
        #expect(filed.importance == chem.importance)
        #expect(filed.estimatedMinutes == chem.estimatedMinutes)
        #expect(filed.nextAction == chem.nextAction)
        #expect(filed.prerequisiteIDs == chem.prerequisiteIDs)
        #expect(filed.parentID == chem.parentID)
        #expect(filed.rejections == chem.rejections)
    }

    @Test("filing finished work away does not un-finish it")
    func archivingKeepsTheCompletionInstant() throws {
        let chem = makeTask(id: "chem")

        let filed = try chem
            .completed(at: .testReference)
            .archived(at: .hoursFromReference(5))

        #expect(filed.completedAt == .testReference)
        #expect(filed.updatedAt == .hoursFromReference(5))
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
        let chem = makeTask(
            id: "chem",
            title: "Chemistry worksheet",
            nextAction: "Question 1.",
            rejections: [rejection(.cantRightNow, hoursAgo: 6)]
        )

        let roundTripped = try chem
            .completed(at: .testReference)
            .reopened(at: .hoursFromReference(1))

        // Everything the user can see is back where it was.
        #expect(roundTripped.status == chem.status)
        #expect(roundTripped.title == chem.title)
        #expect(roundTripped.nextAction == chem.nextAction)
        #expect(roundTripped.deadline == chem.deadline)
        #expect(roundTripped.importance == chem.importance)
        #expect(roundTripped.completedAt == nil)

        // The rejection record survives the whole round trip — it is history, and history is
        // not undone by a completion. Only its power to penalise is.
        #expect(roundTripped.rejections == chem.rejections)
        #expect(roundTripped.activeRejections.isEmpty)

        // The audit trail is the one thing that legitimately differs: the task really was
        // touched twice, and pretending otherwise would make `updatedAt` useless.
        #expect(roundTripped.updatedAt == .hoursFromReference(1))
        #expect(roundTripped.rejectionsSupersededAt == .hoursFromReference(1))
    }

    @Test("reopening keeps everything else about the task intact")
    func reopeningPreservesContent() throws {
        // completed() and archived() both had a preservation test; reopened() did not, and the
        // round-trip fixture above was too thinly seeded to stand in for one — dropping
        // estimatedMinutes, prerequisiteIDs and parentID in reopened() left the whole suite
        // green. Every field a user can lose is named here.
        let chem = makeTask(
            id: "chem",
            title: "Chemistry worksheet",
            deadline: .daysFromReference(1),
            importance: .important,
            estimatedMinutes: 25,
            nextAction: "Do questions 1 to 5.",
            prerequisiteIDs: [TaskID("reading")],
            parentID: TaskID("coursework"),
            rejections: [rejection(.cantRightNow, hoursAgo: 4)]
        )

        let reopened = try chem
            .completed(at: .testReference)
            .reopened(at: .hoursFromReference(1))

        #expect(reopened.title == chem.title)
        #expect(reopened.deadline == chem.deadline)
        #expect(reopened.importance == chem.importance)
        #expect(reopened.estimatedMinutes == chem.estimatedMinutes)
        #expect(reopened.nextAction == chem.nextAction)
        #expect(reopened.prerequisiteIDs == chem.prerequisiteIDs)
        #expect(reopened.parentID == chem.parentID)
        #expect(reopened.rejections == chem.rejections)
        #expect(reopened.createdAt == chem.createdAt)
    }

    @Test("every transition records the instant it was handed")
    func everyTransitionRecordsTheInstant() throws {
        // Five of these used to take `now` and throw it away, so `completed(at: now)` read like
        // a promise the type could not keep.
        let chem = makeTask(id: "chem", createdAt: .daysFromReference(-3))
        let filed = makeTask(id: "filed", status: .archived, createdAt: .daysFromReference(-3))
        let at = Date.hoursFromReference(7)

        let touched = [
            try chem.started(at: at),
            try chem.completed(at: at),
            try chem.archived(at: at),
            try chem.rejected(.other, at: at),
            try chem.withNextAction("Open the brief.", at: at),
            try filed.reopened(at: at)
        ]

        #expect(touched.allSatisfy { $0.updatedAt == at })
    }
}

/// Runs `body` and returns the refusal it produced, or `nil` if it did not refuse.
private func refusal(from body: () throws -> TaskItem) -> TaskTransitionError? {
    do {
        _ = try body()
        return nil
    } catch let error as TaskTransitionError {
        return error
    } catch {
        return nil
    }
}

@Suite("TaskItem transitions — refusals")
struct TaskTransitionRefusalTests {

    /// Every refusal the transitions can produce.
    ///
    /// Built here rather than published from the error type as `CaseIterable`. `notActive`
    /// carries a payload, so the only mechanical version maps over `TaskStatus.allCases` and
    /// yields `.notActive(.active)` — a refusal `requireActive()` cannot throw, since an active
    /// task is exactly what it lets through. That belongs in neither the public API nor a sweep
    /// list, so the list lives with the tests that use it and `refusalsAreAllReachable` proves
    /// it is the real set rather than one someone has to remember to update.
    static let everyRefusal: [TaskTransitionError] =
        TaskStatus.allCases
            .filter { $0 != .active }
            .map { TaskTransitionError.notActive($0) }
        + [.alreadyActive, .alreadyArchived, .emptyNextAction]

    @Test("every refusal in the sweep list is one a transition genuinely throws")
    func refusalsAreAllReachable() {
        let done = makeTask(id: "done", status: .completed)
        let filed = makeTask(id: "filed", status: .archived)
        let chem = makeTask(id: "chem", status: .active)

        let thrown = [
            refusal { try done.started(at: .testReference) },
            refusal { try filed.started(at: .testReference) },
            refusal { try chem.reopened(at: .testReference) },
            refusal { try filed.archived(at: .testReference) },
            refusal { try chem.withNextAction("   \n ", at: .testReference) }
        ].compactMap { $0 }

        #expect(Set(thrown) == Set(Self.everyRefusal))
    }

    @Test("an outstanding task is never refused for its state")
    func activeTaskIsNeverRefusedForItsState() {
        // This is why `.notActive(.active)` must not be published: it is not merely absent from
        // the sweep list, it is a value the guard cannot construct.
        let chem = makeTask(id: "chem", status: .active)

        #expect(refusal { try chem.started(at: .testReference) } == nil)
        #expect(refusal { try chem.completed(at: .testReference) } == nil)
        #expect(refusal { try chem.rejected(.other, at: .testReference) } == nil)
        #expect(refusal { try chem.archived(at: .testReference) } == nil)
        #expect(refusal { try chem.withNextAction("Open the brief.", at: .testReference) } == nil)
    }

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

    @Test("every refusal carries a diagnostic somebody actually wrote")
    func refusalsHaveAuthoredDiagnostics() {
        // The sweep below is only worth running against real text. Before these existed the
        // only string a refusal produced was the compiler's rendering of the case name, so the
        // sweep was inspecting Swift identifiers and could not detect a shaming diagnostic
        // arriving by any other route. Distinctness is what stops the diagnostics being
        // hollowed out to a shared constant while the sweep stays green.
        let texts = Self.everyRefusal.map(\.debugDescription)

        #expect(Set(texts).count == texts.count)
        #expect(texts.allSatisfy { !$0.contains("TaskTransitionError") })
        #expect(TaskTransitionError.notActive(.completed).debugDescription.contains("completed"))
        #expect(TaskTransitionError.notActive(.archived).debugDescription.contains("archived"))
    }

    @Test("refusal diagnostics stay factual and never address the user")
    func refusalsAreNotUserFacing() {
        // These are developer diagnostics. P5 forbids productivity morality anywhere it could
        // reach a screen, so nothing here may read as a judgement.
        let banned = [
            "you", "your", "fail", "behind", "again", "still", "lazy", "streak", "should"
        ]

        for error in Self.everyRefusal {
            // Both strings, not just the one this type currently vends. `debugDescription` is
            // what a developer prints; `localizedDescription` is what reaches an alert or a log,
            // and it is the likelier leak path of the two. Sweeping only the first left a real
            // hole: adding a `LocalizedError` conformance whose `errorDescription` read
            // "You failed again..." kept the entire suite green.
            let surfaces = [error.debugDescription, (error as any Error).localizedDescription]

            for surface in surfaces {
                let text = surface.lowercased()
                for word in banned {
                    #expect(
                        !text.contains(word),
                        "\(error) exposes banned language '\(word)' via: \(surface)"
                    )
                }
            }
        }
    }
}
