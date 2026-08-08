import Foundation
import Testing

@testable import NextKit

// The engine must always return an *explainable* outcome. "No recommendation" is never a bare
// nil — the product spec requires NEXT to say why there is nothing to do rather than silently
// showing an empty screen or recycling an ineligible task.

@Suite("RankingEngine — outcome states")
struct RankingEngineOutcomeTests {

    let engine = RankingEngine()
    let context = RankingContext(now: .testReference)

    @Test("with no tasks at all, reports there is nothing to do")
    func noTasksReportsNothingToDo() {
        let outcome = engine.recommend(from: [], context: context)

        #expect(outcome == .nothingToDo)
    }

    @Test("with every task completed, reports nothing available rather than nothing to do")
    func allCompletedReportsNoActiveTasks() {
        let tasks = [
            makeTask(id: "a", title: "Chemistry worksheet", status: .completed),
            makeTask(id: "b", title: "History essay", status: .completed)
        ]

        let outcome = engine.recommend(from: tasks, context: context)

        #expect(outcome == .nothingAvailable(.noActiveTasks))
    }

    @Test("with one eligible task, recommends that task")
    func singleEligibleTaskIsRecommended() throws {
        let chemistry = makeTask(id: "chem", title: "Chemistry worksheet")

        let outcome = engine.recommend(from: [chemistry], context: context)

        let recommendation = try #require(outcome.recommendation)
        #expect(recommendation.task.id == chemistry.id)
    }

    @Test("ignores completed tasks when an active one exists")
    func completedTasksAreNotRecommended() throws {
        let done = makeTask(id: "done", title: "Already finished", status: .completed)
        let todo = makeTask(id: "todo", title: "Still outstanding")

        let outcome = engine.recommend(from: [done, todo], context: context)

        let recommendation = try #require(outcome.recommendation)
        #expect(recommendation.task.id == todo.id)
    }

    @Test("ignores archived tasks")
    func archivedTasksAreNotRecommended() {
        let archived = makeTask(id: "arch", title: "Dropped module", status: .archived)

        let outcome = engine.recommend(from: [archived], context: context)

        #expect(outcome == .nothingAvailable(.noActiveTasks))
    }
}
