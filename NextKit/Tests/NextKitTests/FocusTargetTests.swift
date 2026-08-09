import Foundation
import Testing

@testable import NextKit

/// What Focus is pointed at, and what finishing it means.
///
/// This type exists because of a real defect: Rescue would shrink a task to "Open the assignment
/// instructions.", the user would tap "Do that", and Focus would open on *the essay* — the exact
/// mountain they had just said was too much. The step was computed, shown, and then dropped on
/// the way to the screen that was supposed to act on it.
///
/// Everything here is a rule about propagation, which is why it is in `NextKit` and not in a view.
@Suite("FocusTarget — what the user is actually working on")
struct FocusTargetTests {

    private func essay(nextAction: String? = nil) -> TaskItem {
        makeTask(id: "essay", title: "History essay", nextAction: nextAction)
    }

    // MARK: The ordinary case

    @Test("focusing a recommendation shows the action the user recorded")
    func recommendedUsesRecordedNextAction() {
        let target = FocusTarget(recommending: essay(nextAction: "Write the introduction."))

        #expect(target.action == "Write the introduction.")
        #expect(target.parentTitle == "History essay")
    }

    @Test("a task with no recorded action is its own action")
    func recommendedFallsBackToTheTitle() {
        let target = FocusTarget(recommending: essay())

        #expect(target.action == "History essay")
    }

    @Test("the task name is dropped when it would only repeat the action")
    func recommendedDoesNotRepeatItself() {
        // One line of context is useful; the same line twice is noise on a screen whose entire
        // job is to show one thing.
        let target = FocusTarget(recommending: essay())

        #expect(target.parentTitle == nil)
    }

    @Test("a blank recorded action is treated as no action at all")
    func blankNextActionFallsBack() {
        let target = FocusTarget(recommending: essay(nextAction: "   \n "))

        #expect(target.action == "History essay")
    }

    @Test("finishing a recommended task finishes the task")
    func recommendedCompletesTheTask() {
        #expect(FocusTarget(recommending: essay()).completesTask)
        #expect(FocusTarget(recommending: essay()).isReduced == false)
    }

    // MARK: Rescue

    private func rescueResponse(
        path: RescuePath = .dontKnowHowToStart,
        taskID: String = "essay",
        title: String? = "History essay",
        step: String = "Open the assignment instructions."
    ) -> RescueResponse {
        RescueResponse(
            path: path,
            taskID: TaskID(taskID),
            taskTitle: title,
            framing: .startHere,
            step: RescueStep(text: step, origin: .generic),
            stepNumber: 1,
            hasMoreSteps: false,
            commitmentMinutes: nil
        )
    }

    @Test("a rescued step is what Focus shows, not the task it came from")
    func rescueStepReachesFocus() {
        // The defect this whole type exists for.
        let target = FocusTarget.rescued(rescueResponse(), among: [essay(nextAction: "Write it.")])

        #expect(target?.action == "Open the assignment instructions.")
    }

    @Test("finishing a rescued step does not finish the whole task")
    func rescueStepDoesNotCompleteTheTask() {
        // Someone who spent five minutes opening the instructions has not written the essay, and
        // an app that marks it done has destroyed something they cannot get back by hand.
        let target = FocusTarget.rescued(rescueResponse(), among: [essay()])

        #expect(target?.isReduced == true)
        #expect(target?.completesTask == false)
    }

    @Test("the parent task is named when the rescue path names it")
    func rescueKeepsTheParentTitleWhenItIsShown() {
        let target = FocusTarget.rescued(rescueResponse(), among: [essay()])

        #expect(target?.parentTitle == "History essay")
    }

    @Test("the parent task stays hidden when the rescue path hid it")
    func rescueHonoursAWithheldTitle() {
        // "It's too much" withholds the title on purpose — naming the mountain is what made it
        // too much. Focus re-displaying it would undo the only thing that path does.
        let withheld = rescueResponse(path: .tooMuch, title: nil)

        let target = FocusTarget.rescued(withheld, among: [essay()])

        #expect(target?.parentTitle == nil)
        #expect(target?.action == "Open the assignment instructions.")
    }

    @Test("Focus follows the task the rescue named, not the one that was asked about")
    func rescueCanRedirectToADifferentTask() {
        // The "I don't have enough time" path re-ranks against the stated window, so it can come
        // back about a different task entirely. Assuming the answer is about the task on screen
        // would open Focus on the wrong work while displaying the right step.
        let chemistry = makeTask(id: "chem", title: "Chemistry worksheet")
        let response = rescueResponse(taskID: "chem", title: "Chemistry worksheet", step: "Do question 1.")

        let target = FocusTarget.rescued(response, among: [essay(), chemistry])

        #expect(target?.task.id == TaskID("chem"))
        #expect(target?.action == "Do question 1.")
    }

    @Test("a rescue naming a task that is gone focuses nothing rather than guessing")
    func rescueForAMissingTaskIsRefused() {
        let target = FocusTarget.rescued(rescueResponse(taskID: "deleted"), among: [essay()])

        #expect(target == nil)
    }

    // MARK: Minimum Win

    private func plan(
        taskID: String = "essay",
        goal: String = "Write the introduction."
    ) -> MinimumWinPlan {
        MinimumWinPlan(
            taskID: TaskID(taskID),
            taskTitle: "History essay",
            minutesRemaining: 90,
            source: .genericStages(.writing),
            framing: .hereIsWhatFits(minutesRemaining: 90),
            best: MinimumWinRung(
                goal: MinimumWinStep(
                    text: goal,
                    minutes: 40,
                    origin: .stage(.outline),
                    hasRecordedDuration: false
                ),
                minutes: 40
            ),
            smallerRungs: [],
            reassessAt: nil
        )
    }

    @Test("choosing a rung focuses that rung's goal")
    func minimumWinRungReachesFocus() {
        let ladder = plan()

        let target = FocusTarget.minimumWin(ladder.best, in: ladder, among: [essay()])

        #expect(target?.action == "Write the introduction.")
        #expect(target?.parentTitle == "History essay")
    }

    @Test("finishing a reduced goal does not finish the whole task")
    func minimumWinDoesNotCompleteTheTask() {
        // The point of Minimum Win is that the whole thing is no longer reachable. Marking it
        // complete would be the app contradicting the reason it offered the ladder.
        let ladder = plan()

        let target = FocusTarget.minimumWin(ladder.best, in: ladder, among: [essay()])

        #expect(target?.isReduced == true)
        #expect(target?.completesTask == false)
    }

    @Test("a ladder for a task that is gone focuses nothing")
    func minimumWinForAMissingTaskIsRefused() {
        let target = FocusTarget.minimumWin(plan(taskID: "deleted").best, in: plan(taskID: "deleted"), among: [essay()])

        #expect(target == nil)
    }

    @Test("every reduced origin agrees it is reduced")
    func reducedOriginsAreConsistent() {
        // A new origin added later must decide this deliberately rather than inherit `false` by
        // being written next to `.recommendation`.
        #expect(FocusOrigin.recommendation.isReduced == false)
        #expect(FocusOrigin.minimumWin.isReduced)
        for path in RescuePath.allCases {
            #expect(FocusOrigin.rescue(path).isReduced, "\(path) should be a reduced action")
        }
    }
}
