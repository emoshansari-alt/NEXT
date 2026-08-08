import Foundation
import Testing

@testable import NextKit

// Covers the "blocked task", "completed parent with pending child" and "unlock value" cases
// from PRODUCT_SPEC.md §5.

@Suite("RankingEngine — prerequisites and unlocking")
struct RankingPrerequisiteTests {

    let engine = RankingEngine()
    let context = RankingContext(now: .testReference)

    @Test("a task waiting on an unfinished prerequisite is not recommended")
    func blockedTaskIsFiltered() throws {
        let research = makeTask(id: "research", deadline: .daysFromReference(3))
        let write = makeTask(
            id: "write",
            deadline: .hoursFromReference(2),
            prerequisiteIDs: [TaskID("research")]
        )

        let outcome = engine.recommend(from: [write, research], context: context)

        // "write" is far more urgent, so only the prerequisite filter explains this.
        #expect(try #require(outcome.recommendation).task.id == research.id)
    }

    @Test("a task becomes available once its prerequisite is completed")
    func completedPrerequisiteUnblocks() throws {
        let research = makeTask(id: "research", status: .completed)
        let write = makeTask(
            id: "write",
            deadline: .hoursFromReference(2),
            prerequisiteIDs: [TaskID("research")]
        )

        let outcome = engine.recommend(from: [write, research], context: context)

        #expect(try #require(outcome.recommendation).task.id == write.id)
    }

    @Test("a prerequisite that no longer exists does not strand the task")
    func danglingPrerequisiteDoesNotBlock() throws {
        // A deleted prerequisite must never leave work permanently unreachable.
        let orphan = makeTask(
            id: "orphan",
            deadline: .daysFromReference(1),
            prerequisiteIDs: [TaskID("deleted-long-ago")]
        )

        let outcome = engine.recommend(from: [orphan], context: context)

        #expect(try #require(outcome.recommendation).task.id == orphan.id)
    }

    @Test("when everything outstanding is blocked, the engine says so")
    func everythingBlockedIsExplained() {
        let gate = makeTask(id: "gate", status: .archived)
        let a = makeTask(id: "a", prerequisiteIDs: [TaskID("gate")])
        let b = makeTask(id: "b", prerequisiteIDs: [TaskID("gate")])

        let outcome = engine.recommend(from: [gate, a, b], context: context)

        #expect(outcome == .nothingAvailable(.everythingBlocked))
    }

    @Test("a completed parent does not hide its outstanding child")
    func completedParentDoesNotBlockChild() throws {
        // Completing the umbrella task must not silently swallow the steps still left in it.
        let parent = makeTask(id: "essay", status: .completed)
        let child = makeTask(
            id: "conclusion", deadline: .daysFromReference(1), parentID: TaskID("essay")
        )

        let outcome = engine.recommend(from: [parent, child], context: context)

        #expect(try #require(outcome.recommendation).task.id == child.id)
    }

    @Test("a task that unblocks other work outranks an equivalent one that does not")
    func unlockingWorkScoresHigher() throws {
        let deadline = Date.daysFromReference(4)
        let gate = makeTask(id: "gate", deadline: deadline)
        let standalone = makeTask(id: "standalone", deadline: deadline)
        let dependent = makeTask(
            id: "dependent", deadline: deadline, prerequisiteIDs: [TaskID("gate")]
        )

        let outcome = engine.recommend(
            from: [standalone, gate, dependent], context: context
        )

        #expect(try #require(outcome.recommendation).task.id == gate.id)
    }

    @Test("unlocking more work scores higher than unlocking less")
    func unlockValueScalesWithDependents() {
        let one = makeTask(id: "one")
        let many = makeTask(id: "many")
        let tasks = [
            one, many,
            makeTask(id: "d1", prerequisiteIDs: [TaskID("one")]),
            makeTask(id: "d2", prerequisiteIDs: [TaskID("many")]),
            makeTask(id: "d3", prerequisiteIDs: [TaskID("many")])
        ]

        let oneUnlock = engine.score(one, among: tasks, context: context)
            .factors[.unlockValue] ?? 0
        let manyUnlock = engine.score(many, among: tasks, context: context)
            .factors[.unlockValue] ?? 0

        #expect(manyUnlock > oneUnlock)
        #expect(oneUnlock > 0)
    }

    @Test("a completed dependent no longer counts toward unlock value")
    func completedDependentsDoNotCount() {
        let gate = makeTask(id: "gate")
        let tasks = [
            gate,
            makeTask(id: "done", status: .completed, prerequisiteIDs: [TaskID("gate")])
        ]

        let score = engine.score(gate, among: tasks, context: context)

        #expect(score.factors[.unlockValue] == 0)
    }
}

@Suite("RankingEngine — startability")
struct RankingStartabilityTests {

    let engine = RankingEngine()
    let context = RankingContext(now: .testReference)

    @Test("a task with a concrete next action outranks an equivalent vague one")
    func knownNextActionScoresHigher() throws {
        let deadline = Date.daysFromReference(4)
        let vague = makeTask(id: "vague", title: "Sort out chemistry", deadline: deadline)
        let concrete = makeTask(
            id: "concrete",
            title: "Chemistry worksheet",
            deadline: deadline,
            nextAction: "Do questions 1 to 5."
        )

        let outcome = engine.recommend(from: [vague, concrete], context: context)

        #expect(try #require(outcome.recommendation).task.id == concrete.id)
    }

    @Test("a blank next action does not count as startable")
    func whitespaceNextActionIsNotStartable() {
        let blank = makeTask(id: "blank", nextAction: "   ")

        let score = engine.score(blank, among: [blank], context: context)

        #expect(score.factors[.startability] == 0)
    }
}
