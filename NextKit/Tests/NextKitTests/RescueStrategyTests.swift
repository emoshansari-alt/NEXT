import Foundation
import Testing

@testable import NextKit

// Rescue is a first-class feature with four fixed entry points, not a help page and never a
// chatbot (PRODUCT_SPEC.md §4.11). Each path behaves differently, and the differences are the
// whole point — a single "here is a smaller step" answer wearing four labels would be a
// regression even though every test of a single path would still pass.

@Suite("Rescue — I don't know how to start")
struct RescueDontKnowHowToStartTests {

    let rescue = RescueStrategy()

    // Three template steps, so there is a ladder to walk.
    let essay = makeTask(id: "essay", title: "Finish history essay")

    @Test("the first ask reveals the smallest physical action")
    func firstAskGivesTheFirstStep() {
        let response = rescue.dontKnowHowToStart(with: essay)

        #expect(response.path == .dontKnowHowToStart)
        #expect(response.step.text == "Open the assignment instructions.")
        #expect(response.framing == .startHere)
        #expect(response.stepNumber == 1)
        #expect(response.hasMoreSteps)
    }

    @Test("exactly one step is ever shown, however long the decomposition is")
    func onlyOneStepIsExposed() {
        // Momentum matters more than exposing the whole decomposition. The response carries
        // one step and a framing line — there is no list for a view to accidentally render.
        let response = rescue.dontKnowHowToStart(with: essay)

        #expect(response.lines == ["Start here.", "Open the assignment instructions."])
    }

    @Test("asking again reveals the next rung, not a repeat")
    func secondAskAdvances() {
        let response = rescue.dontKnowHowToStart(with: essay, stepsAlreadyRevealed: 1)

        #expect(response.step.text == "Open a blank document and type the title.")
        #expect(response.framing == .thenThis)
        #expect(response.stepNumber == 2)
        #expect(response.hasMoreSteps)
    }

    @Test("the last rung reports that there is nothing further hidden")
    func lastStepHasNoMore() {
        let response = rescue.dontKnowHowToStart(with: essay, stepsAlreadyRevealed: 2)

        #expect(response.step.text == "Write one paragraph.")
        #expect(!response.hasMoreSteps)
    }

    @Test("running off the end of the ladder holds at the last rung")
    func revealBeyondTheEndClamps() {
        let response = rescue.dontKnowHowToStart(with: essay, stepsAlreadyRevealed: 99)

        #expect(response.step.text == "Write one paragraph.")
        #expect(response.stepNumber == 3)
        #expect(!response.hasMoreSteps)
    }

    @Test("a nonsensical reveal count cannot produce a nonsensical step")
    func negativeRevealClamps() {
        let response = rescue.dontKnowHowToStart(with: essay, stepsAlreadyRevealed: -4)

        #expect(response.stepNumber == 1)
        #expect(response.step.text == "Open the assignment instructions.")
    }

    @Test("a recorded next action is used instead of an inferred one")
    func recordedActionIsUsed() {
        let task = makeTask(
            id: "essay", title: "Finish history essay", nextAction: "Find three sources"
        )

        let response = rescue.dontKnowHowToStart(with: task)

        #expect(response.step.text == "Find three sources.")
        #expect(response.step.origin == .recordedNextAction)
        #expect(!response.hasMoreSteps)
    }

    @Test("numbered substeps are walked one at a time, and more are admitted to exist")
    func numberedSubstepsFormAWalkableLadder() {
        let parent = makeTask(id: "maths", title: "Maths worksheet")
        let children = (1...3).map {
            makeTask(
                id: "c\($0)", title: "Answer question \($0)",
                parentID: TaskID("maths"), createdAt: .hoursFromReference(Double($0))
            )
        }
        let all = [parent] + children

        let first = rescue.dontKnowHowToStart(with: parent, among: all)

        #expect(first.step.text == "Answer question 1.")
        #expect(first.hasMoreSteps)

        let second = rescue.dontKnowHowToStart(with: parent, among: all, stepsAlreadyRevealed: 1)

        #expect(second.step.text == "Answer question 2.")
        #expect(second.hasMoreSteps)

        let third = rescue.dontKnowHowToStart(with: parent, among: all, stepsAlreadyRevealed: 2)

        #expect(third.step.text == "Answer question 3.")
        #expect(!third.hasMoreSteps)
    }

    @Test("the task is named, because knowing what this belongs to is not the problem here")
    func theTaskIsNamed() {
        #expect(rescue.dontKnowHowToStart(with: essay).taskTitle == "Finish history essay")
    }
}

@Suite("Rescue — it's too much")
struct RescueTooMuchTests {

    let rescue = RescueStrategy()

    @Test("the mountain is hidden: no task title and no hint that more steps exist")
    func theMountainIsHidden() {
        // This is the behavioural difference from "I don't know how to start". The same task
        // has a three-rung ladder there; here the size of the thing is deliberately not shown.
        let task = makeTask(id: "essay", title: "Finish history essay")

        let response = rescue.tooMuch(with: task)

        #expect(response.path == .tooMuch)
        #expect(response.taskTitle == nil)
        #expect(!response.hasMoreSteps)
        #expect(response.framing == .forgetTheRestForNow)
    }

    @Test("the smallest known piece is chosen, not merely the first")
    func smallestPieceIsChosen() {
        // "It's too much" is about size, so size decides — even when the small piece is
        // second in the decomposition.
        let parent = makeTask(id: "essay", title: "Finish history essay")
        let big = makeTask(
            id: "c1", title: "Draft the introduction", estimatedMinutes: 45,
            parentID: TaskID("essay"), createdAt: .hoursFromReference(1)
        )
        let small = makeTask(
            id: "c2", title: "Find one source", estimatedMinutes: 10,
            parentID: TaskID("essay"), createdAt: .hoursFromReference(2)
        )

        let response = rescue.tooMuch(with: parent, among: [parent, big, small])

        #expect(response.step.text == "Find one source.")
        #expect(response.step.origin == .substep(TaskID("c2")))
    }

    @Test("with no sizes recorded, the earliest step is the small one")
    func unsizedStepsFallBackToOrder() {
        let parent = makeTask(id: "essay", title: "Finish history essay")
        let first = makeTask(
            id: "c1", title: "Find one source",
            parentID: TaskID("essay"), createdAt: .hoursFromReference(1)
        )
        let second = makeTask(
            id: "c2", title: "Draft the introduction",
            parentID: TaskID("essay"), createdAt: .hoursFromReference(2)
        )

        let response = rescue.tooMuch(with: parent, among: [parent, second, first])

        #expect(response.step.text == "Find one source.")
    }

    @Test("an unsized earlier rung is not displaced by a large sized one")
    func unsizedEarlierRungBeatsABigSizedOne() {
        // The user said the thing is too much. A rung whose length nobody recorded is not
        // thereby infinitely long, and handing back the forty-five-minute piece because it is
        // the only one carrying a number is handing back the mountain (PRODUCT_SPEC.md §4.11).
        let parent = makeTask(
            id: "essay", title: "Finish history essay", nextAction: "Open the brief"
        )
        let big = makeTask(
            id: "c1", title: "Draft the introduction", estimatedMinutes: 45,
            parentID: TaskID("essay"), createdAt: .hoursFromReference(1)
        )

        let response = rescue.tooMuch(with: parent, among: [parent, big])

        #expect(response.step.text == "Open the brief.")
        #expect(response.step.origin == .recordedNextAction)
    }

    @Test("a sized first rung still yields to a smaller sized one")
    func sizedFirstRungYieldsToASmallerOne() {
        // The other side of the same rule: when both rungs state a length, size decides.
        let parent = makeTask(id: "essay", title: "Finish history essay")
        let big = makeTask(
            id: "c1", title: "Draft the introduction", estimatedMinutes: 45,
            parentID: TaskID("essay"), createdAt: .hoursFromReference(1)
        )
        let small = makeTask(
            id: "c2", title: "Find one source", estimatedMinutes: 10,
            parentID: TaskID("essay"), createdAt: .hoursFromReference(2)
        )
        let unsized = makeTask(
            id: "c3", title: "Reread the notes",
            parentID: TaskID("essay"), createdAt: .hoursFromReference(3)
        )

        let response = rescue.tooMuch(with: parent, among: [parent, big, small, unsized])

        #expect(response.step.text == "Find one source.")
    }

    @Test("the whole response is two lines: set the rest aside, do this")
    func responseIsTwoLines() {
        let task = makeTask(id: "essay", title: "Finish history essay")

        #expect(
            rescue.tooMuch(with: task).lines
                == ["Forget the rest of it for now.", "Open the assignment instructions."]
        )
    }
}

@Suite("Rescue — I don't have enough time")
struct RescueNotEnoughTimeTests {

    let rescue = RescueStrategy()

    @Test("the ranking engine picks the task, so the time budget is a hard constraint")
    func rankingEnginePicksWithinTheWindow() throws {
        // The essay is far more urgent and would win on the Today screen. It cannot be done
        // in fifteen minutes, so it is not offered here. This is the existing engine doing
        // the work — Rescue does not reimplement ranking.
        let essay = makeTask(
            id: "essay", title: "Finish history essay",
            deadline: .hoursFromReference(2), estimatedMinutes: 180
        )
        let worksheet = makeTask(
            id: "worksheet", title: "Maths worksheet",
            deadline: .daysFromReference(3), estimatedMinutes: 15,
            nextAction: "Answer questions 1 to 5"
        )

        let outcome = rescue.notEnoughTime(.fifteen, from: [essay, worksheet], now: .testReference)
        let response = try #require(outcome.response)

        #expect(response.path == .notEnoughTime)
        #expect(response.taskID == TaskID("worksheet"))
        #expect(response.step.text == "Answer questions 1 to 5.")
        #expect(response.framing == .theWholeThingFits(minutes: 15))
        #expect(response.commitmentMinutes == 15)
    }

    @Test("every offered window is decisive, and never offers more than it holds")
    func eachBudgetBehaves() throws {
        // The four choices are the whole of the user's input to this path, and once a deadline
        // has passed it is the *only* route to a smaller goal (D-030) — so each is exercised
        // rather than trusting that a test of fifteen minutes covers five.
        //
        // "Decisive" is the claim, not "always a step". The ranking engine treats the window as
        // a hard constraint and drops a task that cannot fit it, so a twenty-minute task and a
        // five-minute window produce an explicit "nothing fits, the shortest is twenty" — which
        // is an answer. Silence would not be.
        let worksheet = makeTask(
            id: "worksheet", title: "Maths worksheet",
            deadline: .daysFromReference(3), estimatedMinutes: 20,
            nextAction: "Answer questions 1 to 5"
        )

        for budget in TimeBudget.allCases {
            let outcome = rescue.notEnoughTime(budget, from: [worksheet], now: .testReference)

            if let response = outcome.response {
                #expect(response.path == .notEnoughTime)
                #expect(response.commitmentMinutes == budget.minutes)
                if let offered = response.step.estimatedMinutes {
                    #expect(offered <= budget.minutes, "\(budget.minutes) min offered \(offered)")
                }
            } else if case .nothingAvailable(let reason) = outcome {
                #expect(
                    reason == .nothingFitsAvailableTime(shortestMinutes: 20),
                    "\(budget.minutes) min should say what the shortest thing is"
                )
                #expect(budget.minutes < 20, "\(budget.minutes) min is long enough to fit this")
            } else {
                Issue.record("\(budget.minutes) min produced neither guidance nor a reason")
            }
        }
    }

    @Test("a task whose deadline has already passed is still answerable here")
    func anOverdueTaskStillGetsAWindow() throws {
        // The case D-030 turns on. `MinimumWinPlanner` declines once the deadline has gone,
        // because its window *is* the time before the deadline. This path never consults the
        // deadline at all — it plans against what the user says they have now — so it answers
        // exactly as it would for anything else. That is why Today routes "What can I still do?"
        // here instead of growing a second planner.
        let overdue = makeTask(
            id: "worksheet", title: "Chemistry worksheet",
            deadline: .daysFromReference(-2), estimatedMinutes: 25,
            nextAction: "Do questions 1 to 5"
        )

        let outcome = rescue.notEnoughTime(.thirty, from: [overdue], now: .testReference)
        let response = try #require(outcome.response)

        #expect(response.path == .notEnoughTime)
        #expect(response.taskID == TaskID("worksheet"))
        #expect(response.commitmentMinutes == 30)
    }

    @Test("a task of unknown length is offered as one step, not as the whole thing")
    func unsizedTaskIsOfferedAsAStep() throws {
        let essay = makeTask(id: "essay", title: "Finish history essay")

        let outcome = rescue.notEnoughTime(.five, from: [essay], now: .testReference)
        let response = try #require(outcome.response)

        #expect(response.framing == .oneStepInTheWindow(minutes: 5))
        #expect(response.step.text == "Open the assignment instructions.")
    }

    @Test("a step that plainly does not fit the window is skipped")
    func oversizedStepIsSkipped() throws {
        // The essay wins on urgency despite having no estimate of its own, so Rescue has to
        // choose a rung of *its* ladder that genuinely fits five minutes.
        let parent = makeTask(
            id: "essay", title: "Finish history essay", deadline: .hoursFromReference(2)
        )
        let big = makeTask(
            id: "c1", title: "Draft the introduction", estimatedMinutes: 45,
            parentID: TaskID("essay"), createdAt: .hoursFromReference(1)
        )
        let small = makeTask(
            id: "c2", title: "Find one source", estimatedMinutes: 5,
            parentID: TaskID("essay"), createdAt: .hoursFromReference(2)
        )

        let outcome = rescue.notEnoughTime(
            .five, from: [parent, big, small], now: .testReference
        )
        let response = try #require(outcome.response)

        #expect(response.taskID == TaskID("essay"))
        #expect(response.step.text == "Find one source.")
    }

    @Test("when no step of the chosen task fits, an honest universal step is offered")
    func nothingFitsFallsBackHonestly() throws {
        let parent = makeTask(id: "thing", title: "Sort out the thing with the bike")
        let big = makeTask(
            id: "c1", title: "Strip the wheel down", estimatedMinutes: 90,
            parentID: TaskID("thing")
        )

        let outcome = rescue.notEnoughTime(.five, from: [parent, big], now: .testReference)
        let response = try #require(outcome.response)

        #expect(response.step == StepShrinker.genericFirstStep)
    }

    @Test("saying the whole thing fits does not hide the rungs that follow the one shown")
    func wholeThingFitsStillAdmitsTheRestOfTheLadder() throws {
        // "The whole thing fits the 15 minutes you have." followed by rung one of three, with
        // nothing said about the other two, is the response contradicting itself. Unlike
        // "it's too much", this path is not hiding the size of anything — it names the task.
        let worksheet = makeTask(
            id: "worksheet", title: "Maths worksheet",
            deadline: .daysFromReference(3), estimatedMinutes: 15
        )

        let outcome = rescue.notEnoughTime(.fifteen, from: [worksheet], now: .testReference)
        let response = try #require(outcome.response)

        #expect(response.framing == .theWholeThingFits(minutes: 15))
        #expect(response.step.text == "Open the worksheet.")
        #expect(response.hasMoreSteps)
    }

    @Test("the step number names the rung actually offered, not always the first")
    func stepNumberNamesTheRungOnScreen() throws {
        // When the earlier rungs are too big, the one shown is further down the ladder.
        // Reporting it as step 1 tells the user they are at the start when they are two rungs
        // in, and contradicts hasMoreSteps, which is computed from the real index.
        let essay = makeTask(
            id: "essay", title: "History essay", deadline: .hoursFromReference(2)
        )
        let tooBig = makeTask(
            id: "c1", title: "Read the full source pack", estimatedMinutes: 90,
            parentID: TaskID("essay")
        )
        let alsoTooBig = makeTask(
            id: "c2", title: "Draft the introduction", estimatedMinutes: 45,
            parentID: TaskID("essay")
        )
        let fits = makeTask(
            id: "c3", title: "Print the brief", estimatedMinutes: 10,
            parentID: TaskID("essay")
        )

        let outcome = rescue.notEnoughTime(
            .fifteen, from: [essay, tooBig, alsoTooBig, fits], now: .testReference
        )
        let response = try #require(outcome.response)

        #expect(response.step.text == "Print the brief.")
        #expect(response.stepNumber == 3)
        #expect(response.hasMoreSteps == false)
    }

    @Test("a single-rung task that fits is not made to look like it has more")
    func aSingleRungTaskAdmitsNothingFurther() throws {
        let worksheet = makeTask(
            id: "worksheet", title: "Maths worksheet",
            deadline: .daysFromReference(3), estimatedMinutes: 15,
            nextAction: "Answer questions 1 to 5"
        )

        let outcome = rescue.notEnoughTime(.fifteen, from: [worksheet], now: .testReference)
        let response = try #require(outcome.response)

        #expect(!response.hasMoreSteps)
    }

    @Test("the honest universal step is not dressed up as one rung of a ladder")
    func genericFallbackAdmitsNothingFurther() throws {
        let parent = makeTask(id: "thing", title: "Sort out the thing with the bike")
        let big = makeTask(
            id: "c1", title: "Strip the wheel down", estimatedMinutes: 90,
            parentID: TaskID("thing")
        )

        let outcome = rescue.notEnoughTime(.five, from: [parent, big], now: .testReference)
        let response = try #require(outcome.response)

        #expect(response.step == StepShrinker.genericFirstStep)
        #expect(!response.hasMoreSteps)
    }

    @Test("when nothing at all fits, Rescue says so and names the shortest thing there is")
    func nothingFitsIsReported() {
        let a = makeTask(id: "a", title: "Maths worksheet", estimatedMinutes: 45)
        let b = makeTask(id: "b", title: "Finish history essay", estimatedMinutes: 180)

        let outcome = rescue.notEnoughTime(.five, from: [a, b], now: .testReference)

        #expect(outcome == .nothingAvailable(.nothingFitsAvailableTime(shortestMinutes: 45)))
        #expect(outcome.response == nil)
    }

    @Test("with no tasks at all, Rescue reports that rather than inventing something")
    func noTasksIsReported() {
        #expect(rescue.notEnoughTime(.thirty, from: [], now: .testReference) == .nothingToDo)
    }

    @Test("the same question gets the same answer, whatever order the tasks arrive in")
    func timeRescueIsDeterministic() {
        let tasks = [
            makeTask(id: "a", title: "Maths worksheet", estimatedMinutes: 15),
            makeTask(id: "b", title: "Email Professor Hale", estimatedMinutes: 10),
            makeTask(id: "c", title: "Read chapter 4", estimatedMinutes: 20)
        ]

        let forwards = rescue.notEnoughTime(.thirty, from: tasks, now: .testReference)
        let backwards = rescue.notEnoughTime(.thirty, from: tasks.reversed(), now: .testReference)

        #expect(forwards == backwards)
        #expect(forwards == rescue.notEnoughTime(.thirty, from: tasks, now: .testReference))
    }
}

@Suite("Rescue — I just don't want to do it")
struct RescueDontWantToTests {

    let rescue = RescueStrategy()

    @Test("the answer is a smaller deal, not a reason")
    func theAnswerIsATinyDeal() {
        // No diagnosis, no lecture, no motivation — friction reduction only.
        let task = makeTask(id: "essay", title: "Finish history essay")

        let response = rescue.dontWantTo(with: task)

        #expect(response.path == .dontWantTo)
        #expect(response.framing == .tinyDeal(minutes: 5))
        #expect(response.commitmentMinutes == 5)
        #expect(response.step.text == "Open the assignment instructions.")
        #expect(!response.hasMoreSteps)
    }

    @Test("when the whole task is shorter than the deal, the deal is the whole task")
    func shortTaskIsOfferedWhole() {
        // Offering "do five minutes" of a three-minute task would be theatre.
        let task = makeTask(id: "mail", title: "Email Professor Hale", estimatedMinutes: 3)

        let response = rescue.dontWantTo(with: task)

        #expect(response.framing == .theWholeThingIsShort(minutes: 3))
        #expect(response.commitmentMinutes == 3)
    }

    @Test("a task exactly the size of the deal counts as short")
    func exactlyTheDealIsShort() {
        let task = makeTask(id: "mail", title: "Email Professor Hale", estimatedMinutes: 5)

        #expect(rescue.dontWantTo(with: task).framing == .theWholeThingIsShort(minutes: 5))
    }

    @Test("a task longer than the deal still only asks for the deal")
    func longerTaskStillOnlyAsksForTheDeal() {
        let task = makeTask(id: "essay", title: "Finish history essay", estimatedMinutes: 6)

        #expect(rescue.dontWantTo(with: task).framing == .tinyDeal(minutes: 5))
    }

    @Test("the size of the deal is configurable in one place, not scattered")
    func dealSizeIsConfigurable() {
        let gentler = RescueStrategy(commitmentMinutes: 2)
        let task = makeTask(id: "essay", title: "Finish history essay")

        #expect(gentler.dontWantTo(with: task).framing == .tinyDeal(minutes: 2))
        #expect(RescueStrategy.defaultCommitmentMinutes == 5)
    }
}

@Suite("Rescue — the time budget")
struct TimeBudgetTests {

    @Test("the offered windows are exactly the four in the product spec")
    func theFourWindows() {
        #expect(TimeBudget.allCases.map(\.minutes) == [5, 15, 30, 60])
    }

    @Test("an hour is described as an hour")
    func labels() {
        #expect(TimeBudget.allCases.map(\.label) == ["5 min", "15 min", "30 min", "1 hour"])
    }

    @Test("a budget can be rebuilt from its minutes, and only from a real one")
    func roundTrip() {
        #expect(TimeBudget(minutes: 30) == .thirty)
        #expect(TimeBudget(minutes: 7) == nil)
    }
}
