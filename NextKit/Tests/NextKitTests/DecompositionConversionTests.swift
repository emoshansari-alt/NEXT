import Foundation
import Testing

@testable import NextKit

// "Break it down" turns one task into its steps. The steps become real tasks linked by
// parentID, which is the shape StepShrinker and MinimumWinPlanner already read — so a
// decomposition immediately improves Rescue and Minimum Win too, rather than being a separate
// feature only Task Detail knows about.
//
// The fixtures go through the real ResponseValidator rather than constructing a `Validated`
// directly: its initialiser is fileprivate precisely so nothing can manufacture trust in an
// unvalidated value, and a test that bypassed that would be exercising a path the app cannot
// reach. It also means empty and blank-text decompositions are not tested here — the validator
// rejects both before conversion is ever called, and `ResponseValidatorTests` covers that.

private let validator = ResponseValidator()

private func decomposition(_ steps: [(String, Int?)]) throws -> Validated<Decomposition> {
    try validator.validate(
        DecompositionResponse(
            steps: steps.map {
                ProposedStep(text: $0.0, estimatedMinutes: $0.1, confidence: 0.9)
            }
        )
    )
}

private final class DecompositionStepIDs: IDProvider, @unchecked Sendable {
    private var next = 0
    private let lock = NSLock()
    func makeTaskID() -> TaskID {
        lock.lock(); defer { lock.unlock() }
        next += 1
        return TaskID("step-\(next)")
    }
}

private func provider() -> DecompositionStepIDs { DecompositionStepIDs() }

@Suite("Decomposition — becoming child tasks")
struct DecompositionConversionTests {

    private let parent = makeTask(
        id: "essay",
        title: "History essay",
        deadline: .daysFromReference(3),
        importance: .important
    )

    @Test("each step becomes a task belonging to the parent")
    func stepsBecomeChildren() throws {
        let result = try decomposition([("Find three sources.", 20), ("Write the outline.", 30)])
            .childTasks(of: parent, idProvider: provider(), createdAt: .testReference)

        #expect(result.map(\.title) == ["Find three sources.", "Write the outline."])
        #expect(result.allSatisfy { $0.parentID == parent.id })
        #expect(result.map(\.estimatedMinutes) == [20, 30])
    }

    @Test("children inherit the deadline, because they are the same obligation")
    func childrenInheritTheDeadline() throws {
        // A step of something due Friday is also due Friday. Leaving children undated would
        // make the engine treat the actual work as having no urgency at all.
        let result = try decomposition([("Find three sources.", 20)])
            .childTasks(of: parent, idProvider: provider(), createdAt: .testReference)

        #expect(result.first?.deadline == parent.deadline)
        #expect(result.first?.importance == parent.importance)
    }

    @Test("ordering is preserved and creation times keep it stable")
    func orderIsPreserved() throws {
        // Steps are a ladder, not a set. The repository orders by createdAt then identifier, so
        // identical instants would leave the rungs to be re-sorted alphabetically — which is
        // not the order the decomposition came in.
        let result = try decomposition([("Read the brief.", nil), ("Find sources.", nil), ("Outline it.", nil)])
            .childTasks(of: parent, idProvider: provider(), createdAt: .testReference)

        #expect(result.map(\.title) == ["Read the brief.", "Find sources.", "Outline it."])
        #expect(result[0].createdAt < result[1].createdAt)
        #expect(result[1].createdAt < result[2].createdAt)
    }

    @Test("the parent's own next action is not duplicated as a step")
    func parentNextActionIsNotDuplicated() throws {
        var withAction = parent
        withAction.nextAction = "Find three sources."

        let result = try decomposition([("Find three sources.", 20), ("Write the outline.", 30)])
            .childTasks(of: withAction, idProvider: provider(), createdAt: .testReference)

        #expect(result.map(\.title) == ["Write the outline."])
    }
}

@Suite("Decomposition — what happens to the parent")
struct DecomposedParentTests {

    private let parent = makeTask(
        id: "essay", title: "History essay", deadline: .daysFromReference(3)
    )

    @Test("the parent waits on its own steps")
    func parentIsBlockedByItsChildren() throws {
        // The parent is the mountain. Once it has steps it must stop competing with them for
        // the recommendation — otherwise breaking a task down makes the screen worse, not
        // better. Expressing that as prerequisites reuses the blocking the engine already does.
        let children = try decomposition([("Find sources.", 20), ("Outline it.", 30)])
            .childTasks(of: parent, idProvider: provider(), createdAt: .testReference)

        #expect(parent.awaiting(children).prerequisiteIDs == children.map(\.id))
    }

    @Test("a broken-down parent is not recommended while its steps are outstanding")
    func brokenDownParentIsNotRecommended() throws {
        let children = try decomposition([("Find sources.", 20)])
            .childTasks(of: parent, idProvider: provider(), createdAt: .testReference)

        let outcome = RankingEngine().recommend(
            from: [parent.awaiting(children)] + children,
            context: RankingContext(now: .testReference)
        )

        #expect(try #require(outcome.recommendation).task.id == children[0].id)
    }

    @Test("finishing every step frees the parent again")
    func completingStepsUnblocksTheParent() throws {
        let children = try decomposition([("Find sources.", 20)])
            .childTasks(of: parent, idProvider: provider(), createdAt: .testReference)
        let done = try children.map { try $0.completed(at: .testReference) }

        let outcome = RankingEngine().recommend(
            from: [parent.awaiting(children)] + done,
            context: RankingContext(now: .testReference)
        )

        #expect(try #require(outcome.recommendation).task.id == parent.id)
    }

    @Test("breaking down twice adds the new steps without losing or duplicating any")
    func awaitingIsAdditiveAndDoesNotDuplicate() throws {
        let first = try decomposition([("Find sources.", 20)])
            .childTasks(of: parent, idProvider: provider(), createdAt: .testReference)
        let second = try decomposition([("Outline it.", 30)])
            .childTasks(of: parent, idProvider: provider(), createdAt: .hoursFromReference(1))

        let updated = parent.awaiting(first).awaiting(second).awaiting(first)

        #expect(updated.prerequisiteIDs.count == Set(updated.prerequisiteIDs).count)
        #expect(Set(updated.prerequisiteIDs) == Set((first + second).map(\.id)))
    }
}
