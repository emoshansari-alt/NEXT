import Foundation
import Testing

@testable import NextApp
import NextKit

/// The three flows that turn built-but-unreachable logic into something a user can actually do:
/// Minimum Win reaching the screen, a rescued step surviving the trip into Focus, and the
/// Focus → stuck → smaller action → Focus loop.
///
/// These are integration tests at the view-model level. They exist because every one of these
/// features was already correct in `NextKit` and still wrong in the app: the defect was never in
/// the logic, it was in what the app did with the answer.

private struct FixedTimeSource: TimeSource {
    let now: Date
}

private let reference = Date(timeIntervalSince1970: 1_773_133_200)  // 2026-03-10 09:00 UTC

private func task(
    _ id: String,
    title: String,
    nextAction: String? = nil,
    deadlineHours: Double? = nil,
    minutes: Int? = nil
) -> TaskItem {
    TaskItem(
        id: TaskID(id),
        title: title,
        createdAt: reference,
        deadline: deadlineHours.map { reference.addingTimeInterval($0 * 3600) },
        estimatedMinutes: minutes,
        nextAction: nextAction
    )
}

@MainActor
private func loaded(_ tasks: [TaskItem]) async -> (TodayViewModel, InMemoryTaskRepository) {
    let repository = InMemoryTaskRepository()
    for item in tasks { try? await repository.upsert(item) }

    let model = TodayViewModel(
        repository: repository,
        timeSource: FixedTimeSource(now: reference)
    )
    await model.load()
    return (model, repository)
}

// MARK: - Rescue into Focus

@MainActor
@Suite("Rescue carries its step into Focus")
struct RescueIntoFocusTests {

    private func rescue(_ model: TodayViewModel, path: RescuePath) -> RescueResponse? {
        guard let current = model.recommendation?.task else { return nil }
        let strategy = RescueStrategy()

        switch path {
        case .dontKnowHowToStart: return strategy.dontKnowHowToStart(with: current, among: model.tasks)
        case .tooMuch: return strategy.tooMuch(with: current, among: model.tasks)
        case .dontWantTo: return strategy.dontWantTo(with: current, among: model.tasks)
        case .notEnoughTime:
            return strategy.notEnoughTime(.fifteen, from: model.tasks, now: reference).response
        }
    }

    @Test("the shrunken step is what Focus shows, not the task it came from")
    func rescuedStepReachesFocus() async throws {
        // The defect: this used to open Focus on the essay — the exact thing the user had just
        // told the app was too much.
        let (model, _) = await loaded([
            task("essay", title: "History essay", deadlineHours: 30)
        ])
        let response = try #require(rescue(model, path: .tooMuch))
        try #require(response.step.text != "History essay", "the step should be smaller than the task")

        await model.focusRescued(response)

        let focus = try #require(model.focus)
        #expect(focus.action == response.step.text)
        #expect(focus.action != "History essay")
    }

    @Test("a recorded next action is offered as written, even when it is a large one")
    func rescueOffersTheUsersOwnWordsUnchanged() async throws {
        // Documenting real behaviour rather than asserting a wish. `StepShrinker` puts a recorded
        // next action at the head of the ladder on purpose — the user wrote it, and nothing
        // inferred from a keyword read of the title beats that.
        //
        // The consequence, stated plainly: someone who records "Write the whole thing." as their
        // next action and then says "It's too much" gets that same sentence back. NEXT is not
        // overruling the user's own words on the strength of a template. It is a real limitation
        // of this path and it is in SESSION_LOG.md, not hidden behind a fixture that avoids it.
        let (model, _) = await loaded([
            task("essay", title: "History essay", nextAction: "Write the whole thing.", deadlineHours: 30)
        ])

        let response = try #require(rescue(model, path: .tooMuch))
        await model.focusRescued(response)

        #expect(response.step.origin == .recordedNextAction)
        // What this test actually guards is the propagation: whatever Rescue decided on, that is
        // what Focus shows.
        #expect(try #require(model.focus).action == response.step.text)
    }

    @Test("finishing a rescued step leaves the task outstanding")
    func rescuedStepDoesNotCompleteTheTask() async throws {
        let (model, repository) = await loaded([
            task("essay", title: "History essay", deadlineHours: 30)
        ])
        let response = try #require(rescue(model, path: .dontKnowHowToStart))
        await model.focusRescued(response)

        await model.completeFocused()

        let stored = try #require(try await repository.fetch(id: TaskID("essay")))
        #expect(stored.status == .active, "the essay is not finished because a step was")
        #expect(model.focus == nil, "Focus still closes")
    }

    @Test("accepting a rescued step records that the task was started")
    func rescuedStepMarksTheTaskStarted() async throws {
        // Started, not completed. It supersedes an earlier "Not this", which matters: someone who
        // passed on a task and then asked for help with it has plainly changed their mind.
        let (model, repository) = await loaded([
            task("essay", title: "History essay", deadlineHours: 30)
        ])
        let response = try #require(rescue(model, path: .dontWantTo))

        await model.focusRescued(response)

        let stored = try #require(try await repository.fetch(id: TaskID("essay")))
        #expect(stored.rejectionsSupersededAt == reference)
        #expect(stored.status == .active)
    }

    @Test("the hidden task name stays hidden in Focus")
    func withheldTitleSurvivesTheTrip() async throws {
        // "It's too much" withholds the title on purpose. Focus re-deriving it from the task
        // would undo the only thing that path does.
        let (model, _) = await loaded([
            task("essay", title: "History essay", deadlineHours: 30)
        ])
        let response = try #require(rescue(model, path: .tooMuch))
        try #require(response.taskTitle == nil)

        await model.focusRescued(response)

        #expect(try #require(model.focus).parentTitle == nil)
    }

    @Test("a rescue that re-ranks focuses the task it actually named")
    func timeBudgetRescueFocusesItsOwnTask() async throws {
        // "I don't have enough time" re-ranks against the stated window, so the answer can be
        // about a different task than the one on screen. Focusing whatever was recommended would
        // open the wrong work while displaying the right step.
        let (model, _) = await loaded([
            task("essay", title: "History essay", deadlineHours: 30, minutes: 180),
            task("email", title: "Email Professor Adeyemi", deadlineHours: 40, minutes: 5)
        ])
        let response = try #require(rescue(model, path: .notEnoughTime))

        await model.focusRescued(response)

        #expect(try #require(model.focus).task.id == response.taskID)
    }

    @Test("a rescue naming a task that has since gone focuses nothing")
    func staleRescueIsHarmless() async throws {
        // Reachable: the store can change under a sheet.
        let (model, repository) = await loaded([
            task("essay", title: "History essay", deadlineHours: 30)
        ])
        let response = try #require(rescue(model, path: .dontKnowHowToStart))

        try await repository.delete(id: TaskID("essay"))
        await model.load()
        await model.focusRescued(response)

        #expect(model.focus == nil)
    }
}

// MARK: - The Focus → stuck → smaller action → Focus loop

@MainActor
@Suite("Focus, stuck, smaller, Focus")
struct FocusRescueLoopTests {

    @Test("being stuck inside Focus replaces the action without leaving Focus")
    func theLoopStaysInFocus() async throws {
        // The whole point of answering from inside Focus: someone who has to leave, find Today
        // and start again has already lost the thread.
        let (model, _) = await loaded([
            task("essay", title: "History essay", nextAction: "Write the whole thing.", deadlineHours: 30)
        ])
        await model.startRecommended()

        let before = try #require(model.focus)
        #expect(before.action == "Write the whole thing.")
        #expect(before.completesTask)

        let response = RescueStrategy().tooMuch(with: before.task, among: model.tasks)
        await model.focusRescued(response)

        let after = try #require(model.focus, "Focus should still be open")
        #expect(after.action == response.step.text)
        #expect(after.completesTask == false)
    }

    @Test("the focus target keeps its identity so Focus updates rather than reopening")
    func identityIsStableAcrossTheLoop() async throws {
        // SwiftUI presents by identity. If the id changed with the action, the loop would dismiss
        // and re-present Focus, which reads as being thrown out of the session.
        let (model, _) = await loaded([
            task("essay", title: "History essay", nextAction: "Write it.", deadlineHours: 30)
        ])
        await model.startRecommended()
        let before = try #require(model.focus)

        let response = RescueStrategy().dontKnowHowToStart(with: before.task, among: model.tasks)
        await model.focusRescued(response)

        #expect(try #require(model.focus).id == before.id)
    }

    @Test("the done button says what it will actually do")
    func doneLabelMatchesTheConsequence() async throws {
        let (model, _) = await loaded([
            task("essay", title: "History essay", deadlineHours: 30)
        ])
        await model.startRecommended()
        let whole = try #require(model.focus)

        let response = RescueStrategy().tooMuch(with: whole.task, among: model.tasks)
        await model.focusRescued(response)
        let step = try #require(model.focus)

        #expect(FocusCopy.doneLabel(for: whole) == "Done")
        #expect(FocusCopy.doneLabel(for: step) == "Done with this step")
    }
}

// MARK: - Minimum Win

@MainActor
@Suite("Minimum Win reaches the screen")
struct MinimumWinFlowTests {

    /// Three hours of work, one hour left. The ideal outcome is genuinely gone.
    private func doomedEssay() -> TaskItem {
        task("essay", title: "History essay", deadlineHours: 1, minutes: 180)
    }

    @Test("a task that cannot be finished in time offers a ladder")
    func unreachableDeadlineProducesAPlan() async throws {
        let (model, _) = await loaded([doomedEssay()])

        let recommendation = try #require(model.recommendation)
        #expect(recommendation.deadlineFeasibility == .unreachable)

        let plan = try #require(model.minimumWinPlan, "the planner finally has a caller")
        #expect(plan.taskID == TaskID("essay"))
        #expect(plan.rungs.isEmpty == false)
    }

    @Test("work that comfortably fits is not offered a ladder")
    func comfortableWorkHasNoPlan() async throws {
        // Offering "what can I still do?" for something that fits would be manufacturing an
        // emergency, which is the opposite of what this app is for.
        let (model, _) = await loaded([
            task("worksheet", title: "Chemistry worksheet", deadlineHours: 30, minutes: 20)
        ])

        #expect(model.recommendation?.deadlineFeasibility != .unreachable)
        #expect(model.minimumWinPlan == nil)
    }

    @Test("a task with no estimate is not given an invented ladder")
    func unknownDurationHasNoPlan() async throws {
        // Every rung's length is a share of the whole estimate, so without one the ladder is
        // assembled entirely out of a number NEXT does not have.
        let (model, _) = await loaded([
            task("essay", title: "History essay", deadlineHours: 1)
        ])

        #expect(model.minimumWinPlan == nil)
    }

    @Test("choosing a rung focuses that rung, not the whole task")
    func choosingARungFocusesIt() async throws {
        let (model, _) = await loaded([doomedEssay()])
        let plan = try #require(model.minimumWinPlan)

        await model.focusMinimumWin(plan.best, in: plan)

        let focus = try #require(model.focus)
        #expect(focus.action == plan.best.goal.text)
        #expect(focus.action != "History essay")
        #expect(focus.completesTask == false)
    }

    @Test("finishing a rung leaves the task outstanding")
    func finishingARungDoesNotCompleteTheTask() async throws {
        // The ladder was offered *because* the whole thing is out of reach. Completing it here
        // would have the app contradict its own reason for showing the screen.
        let (model, repository) = await loaded([doomedEssay()])
        let plan = try #require(model.minimumWinPlan)
        await model.focusMinimumWin(plan.best, in: plan)

        await model.completeFocused()

        let stored = try #require(try await repository.fetch(id: TaskID("essay")))
        #expect(stored.status == .active)
        #expect(model.focus == nil)
    }

    @Test("a smaller rung can be chosen instead of the best one")
    func anySmallerRungCanBeChosen() async throws {
        let (model, _) = await loaded([doomedEssay()])
        let plan = try #require(model.minimumWinPlan)

        guard let smaller = plan.smallerRungs.first else { return }
        await model.focusMinimumWin(smaller, in: plan)

        #expect(try #require(model.focus).action == smaller.goal.text)
    }
}
