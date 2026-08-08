import Foundation
import Testing

@testable import NextKit

// Shrinking is the part of Rescue that can actually be got wrong quietly. A version that
// answers "start the task" for everything would compile, pass a shallow test, and be useless.
//
// These tests therefore pin the priority order the product depends on:
//
//   1. what the user actually recorded  (a next action, then real substeps)
//   2. what the title honestly implies  (verb first, then object noun)
//   3. an honest generic step           (never a confident guess)

@Suite("StepShrinker — recorded work outranks inference")
struct StepShrinkerRecordedTests {

    let shrinker = StepShrinker()

    @Test("a recorded next action is the first step, ahead of anything inferred")
    func recordedNextActionWins() throws {
        // The title alone would infer a writing step. A real recorded action beats it:
        // the user already knows something the engine can only guess at.
        let task = makeTask(
            id: "essay",
            title: "Finish history essay",
            nextAction: "Reread the notes from Thursday"
        )

        let first = try #require(shrinker.steps(for: task).first)

        #expect(first.origin == .recordedNextAction)
        #expect(first.text == "Reread the notes from Thursday.")
    }

    @Test("a next action that is only whitespace is ignored rather than shown as a step")
    func blankNextActionIsIgnored() throws {
        let task = makeTask(id: "essay", title: "Finish history essay", nextAction: "   ")

        let first = try #require(shrinker.steps(for: task).first)

        #expect(first.origin == .template(.writing))
    }

    @Test("existing punctuation on a recorded action is left alone")
    func punctuationIsNotDoubled() throws {
        let task = makeTask(id: "t", title: "Untitled", nextAction: "Which reading is it?")

        let first = try #require(shrinker.steps(for: task).first)

        #expect(first.text == "Which reading is it?")
    }

    @Test("outstanding substeps form the ladder, in creation order not array order")
    func substepsFormTheLadder() {
        let parent = makeTask(id: "essay", title: "Finish history essay")
        let later = makeTask(
            id: "c2", title: "Draft the introduction",
            parentID: TaskID("essay"), createdAt: .hoursFromReference(2)
        )
        let earlier = makeTask(
            id: "c1", title: "Find one source",
            parentID: TaskID("essay"), createdAt: .hoursFromReference(1)
        )

        let steps = shrinker.steps(for: parent, among: [parent, later, earlier])

        #expect(steps.map(\.text) == ["Find one source.", "Draft the introduction."])
        #expect(steps.first?.origin == .substep(TaskID("c1")))
    }

    @Test("a finished substep drops out of the ladder")
    func completedSubstepIsNotOffered() {
        let parent = makeTask(id: "essay", title: "Finish history essay")
        let done = makeTask(
            id: "c1", title: "Find one source", status: .completed,
            parentID: TaskID("essay"), createdAt: .hoursFromReference(1)
        )
        let todo = makeTask(
            id: "c2", title: "Draft the introduction",
            parentID: TaskID("essay"), createdAt: .hoursFromReference(2)
        )

        let steps = shrinker.steps(for: parent, among: [parent, done, todo])

        #expect(steps.map(\.text) == ["Draft the introduction."])
    }

    @Test("a substep's own next action is preferred to its title")
    func substepNextActionPreferred() {
        let parent = makeTask(id: "essay", title: "Finish history essay")
        let child = makeTask(
            id: "c1", title: "Research", nextAction: "Search the library catalogue",
            parentID: TaskID("essay")
        )

        let steps = shrinker.steps(for: parent, among: [parent, child])

        #expect(steps.map(\.text) == ["Search the library catalogue."])
    }

    @Test("a recorded action and substeps combine into one ladder, action first")
    func recordedActionThenSubsteps() {
        let parent = makeTask(
            id: "essay", title: "Finish history essay", nextAction: "Open the brief"
        )
        let child = makeTask(id: "c1", title: "Find one source", parentID: TaskID("essay"))

        let steps = shrinker.steps(for: parent, among: [parent, child])

        #expect(steps.map(\.text) == ["Open the brief.", "Find one source."])
    }

    @Test("a substep repeating the recorded action is not listed twice")
    func duplicateStepsAreCollapsed() {
        let parent = makeTask(
            id: "essay", title: "Finish history essay", nextAction: "Find one source"
        )
        let child = makeTask(id: "c1", title: "find one source.", parentID: TaskID("essay"))

        let steps = shrinker.steps(for: parent, among: [parent, child])

        #expect(steps.count == 1)
    }

    @Test("an unrelated task's children are not borrowed")
    func onlyOwnChildrenCount() {
        let task = makeTask(id: "a", title: "Untitled")
        let strangerChild = makeTask(id: "c", title: "Not mine", parentID: TaskID("b"))

        let steps = shrinker.steps(for: task, among: [task, strangerChild])

        #expect(steps.allSatisfy { $0.origin == .generic })
    }
}

@Suite("StepShrinker — inferring a physical step from the title")
struct StepShrinkerInferenceTests {

    let shrinker = StepShrinker()

    private func firstStep(_ title: String) throws -> RescueStep {
        try #require(shrinker.steps(for: makeTask(id: "t", title: title)).first)
    }

    @Test("the product spec's example shrinks to the product spec's step")
    func specExample() throws {
        // PRODUCT_SPEC.md §4.11: "Finish history essay" → "Open the assignment instructions."
        let step = try firstStep("Finish history essay")

        #expect(step.text == "Open the assignment instructions.")
        #expect(step.origin == .template(.writing))
    }

    @Test("an action verb in the title selects the kind of work")
    func verbsSelectTheKind() throws {
        let cases: [(String, WorkKind)] = [
            ("Email Professor Hale about the extension", .correspondence),
            ("Submit the enrolment form", .admin),
            ("Solve the first ten", .problemSet),
            ("Present the group findings", .presentation),
            ("Revise for the chem test", .revision),
            ("Practise scales", .practice),
            ("Write the conclusion", .writing),
            ("Read chapter 4", .reading)
        ]

        for (title, expected) in cases {
            #expect(try firstStep(title).origin == .template(expected), "wrong kind for \(title)")
        }
    }

    @Test("with no verb, an object noun in the title selects the kind of work")
    func objectNounsSelectTheKind() throws {
        let cases: [(String, WorkKind)] = [
            ("Enrolment form", .admin),
            ("Maths worksheet", .problemSet),
            ("History slides for Friday", .presentation),
            ("Chem test on Monday", .revision),
            ("Piano", .practice),
            ("History essay", .writing),
            ("Biology textbook", .reading)
        ]

        for (title, expected) in cases {
            #expect(try firstStep(title).origin == .template(expected), "wrong kind for \(title)")
        }
    }

    @Test("a verb outranks an object noun, so the action wins over the artefact")
    func verbBeatsNoun() throws {
        // "essay" would infer writing, but the user said *read*. Reading it is the physical act.
        let step = try firstStep("Read the essay")

        #expect(step.origin == .template(.reading))
    }

    @Test("when two verbs compete, the one mentioned first wins")
    func earliestVerbWins() throws {
        // Deterministic and sensible: the first act named is normally the first act needed.
        #expect(try firstStep("Read chapter 4 and write a summary").origin == .template(.reading))
        #expect(try firstStep("Write a summary of chapter 4").origin == .template(.writing))
    }

    @Test("a plural is recognised as readily as a singular")
    func pluralsAreRecognised() throws {
        #expect(try firstStep("Finish the worksheets").origin == .template(.problemSet))
        #expect(try firstStep("History essays").origin == .template(.writing))
    }

    @Test("keywords are matched as whole words, not as substrings")
    func noSubstringFalsePositives() throws {
        // "already" contains "read"; "contest" contains "test". Neither is a signal.
        #expect(try firstStep("Sort out the already sorted pile").origin == .generic)
        #expect(try firstStep("Enter the contest").origin == .generic)
    }

    @Test("an unrecognised title gets an honest generic step, not a confident guess")
    func unknownTitleIsHonest() throws {
        let step = try firstStep("Sort out the thing with the bike")

        #expect(step.origin == .generic)
        #expect(!step.text.isEmpty)
    }

    @Test("an empty title still yields a usable step")
    func emptyTitleStillWorks() throws {
        let step = try firstStep("   ")

        #expect(step.origin == .generic)
        #expect(!step.text.isEmpty)
    }
}

@Suite("StepShrinker — guarantees")
struct StepShrinkerGuaranteeTests {

    let shrinker = StepShrinker()

    @Test("every kind of work has at least one physical step to offer")
    func everyKindHasSteps() {
        for kind in WorkKind.allCases {
            #expect(!kind.firstSteps.isEmpty, "\(kind) has no steps")
            #expect(
                kind.firstSteps.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                "\(kind) has a blank step"
            )
        }
    }

    @Test("the ladder is never empty, whatever the task looks like")
    func ladderIsNeverEmpty() {
        let tasks = [
            makeTask(id: "a", title: ""),
            makeTask(id: "b", title: "Finish history essay"),
            makeTask(id: "c", title: "?!?"),
            makeTask(id: "d", title: "Untitled", nextAction: "  ")
        ]

        for task in tasks {
            #expect(!shrinker.steps(for: task).isEmpty, "empty ladder for '\(task.title)'")
        }
    }

    @Test("a step knows whether it came from the user or from a guess")
    func originsDistinguishRecordedFromInferred() {
        // The app layer needs this to decide whether a step may be presented flatly or
        // should be offered as NEXT's suggestion. Getting it backwards would have the app
        // asserting an inference as though the user had written it.
        #expect(RescueStepOrigin.recordedNextAction.isFromRecordedWork)
        #expect(RescueStepOrigin.substep(TaskID("c")).isFromRecordedWork)
        #expect(!RescueStepOrigin.template(.writing).isFromRecordedWork)
        #expect(!RescueStepOrigin.generic.isFromRecordedWork)
    }

    @Test("the same task always shrinks the same way, whatever order the list arrives in")
    func shrinkingIsDeterministic() {
        let parent = makeTask(id: "p", title: "Finish history essay")
        let children = (1...4).map {
            makeTask(
                id: "c\($0)", title: "Step \($0)",
                parentID: TaskID("p"), createdAt: .hoursFromReference(Double($0))
            )
        }
        let forwards = shrinker.steps(for: parent, among: [parent] + children)
        let backwards = shrinker.steps(for: parent, among: ([parent] + children).reversed())

        #expect(forwards == backwards)
        #expect(forwards == shrinker.steps(for: parent, among: [parent] + children))
    }
}
