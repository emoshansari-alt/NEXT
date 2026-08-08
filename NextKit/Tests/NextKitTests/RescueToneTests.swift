import Foundation
import Testing

@testable import NextKit

// Rescue is reached by someone who is stuck. That is the exact moment a productivity app is
// most tempted to become a coach, a therapist or a cheerleader, and the exact moment NEXT
// must stay a competent tool (PRODUCT_SPEC.md §3, invariant P5).
//
// Modelled on `ExplanationSentenceTests.sentencesAreNeverJudgemental`, and deliberately wider:
// it sweeps every string this module can put in front of a user, so a well-meaning future edit
// to any one template trips it.

/// Every piece of copy the Rescue module can generate, independent of user data.
private func allRescueCopy() -> [String] {
    var copy: [String] = []

    copy += RescuePath.allCases.map(\.prompt)
    copy += TimeBudget.allCases.map(\.label)
    copy += WorkKind.allCases.flatMap(\.firstSteps)
    copy += StepShrinker.genericSteps.map(\.text)

    let framings: [RescueFraming] = [
        .startHere,
        .thenThis,
        .forgetTheRestForNow,
        .tinyDeal(minutes: 1),
        .tinyDeal(minutes: 5),
        .theWholeThingIsShort(minutes: 1),
        .theWholeThingIsShort(minutes: 3),
        .theWholeThingFits(minutes: 15),
        .oneStepInTheWindow(minutes: 60)
    ]
    copy += framings.map(\.sentence)

    // Whole responses too, so a line assembled from parts is checked as it is actually read.
    let rescue = RescueStrategy()
    let task = makeTask(id: "t", title: "Finish history essay", estimatedMinutes: 90)
    let short = makeTask(id: "s", title: "Email Professor Hale", estimatedMinutes: 2)

    for revealed in 0..<4 {
        copy += rescue.dontKnowHowToStart(with: task, stepsAlreadyRevealed: revealed).lines
    }
    copy += rescue.tooMuch(with: task).lines
    copy += rescue.dontWantTo(with: task).lines
    copy += rescue.dontWantTo(with: short).lines
    for budget in TimeBudget.allCases {
        let outcome = rescue.notEnoughTime(budget, from: [task, short], now: .testReference)
        copy += outcome.response?.lines ?? []
    }

    return copy
}

@Suite("Rescue — tone")
struct RescueToneTests {

    @Test("nothing Rescue says implies the user has fallen short")
    func neverShames() {
        let banned = [
            "failed", "fail", "behind", "streak", "again", "still haven't", "lazy",
            "should have", "you didn't", "you never", "miss you", "wasted",
            "procrastinat", "excuse", "give up", "slack"
        ]

        for line in allRescueCopy() {
            let lowered = line.lowercased()
            for word in banned {
                #expect(!lowered.contains(word), "'\(word)' appears in: \(line)")
            }
        }
    }

    @Test("nothing Rescue says is a pep talk")
    func neverMotivates() {
        // Restraint is the product identity. "Start with questions 1-5." beats encouragement,
        // and encouragement from software the user did not ask for reads as condescension.
        let banned = [
            "you've got this", "you can do it", "amazing", "great job", "well done",
            "keep it up", "proud", "believe in", "crush it", "smash it",
            "motivat", "willpower", "discipline", "champion", "journey"
        ]

        for line in allRescueCopy() {
            let lowered = line.lowercased()
            for word in banned {
                #expect(!lowered.contains(word), "'\(word)' appears in: \(line)")
            }
        }
    }

    @Test("nothing Rescue says frames the user as having a condition")
    func neverDiagnoses() {
        // A hard product boundary, not a stylistic preference (PRODUCT_SPEC.md §1). Rescue
        // addresses a task that is hard to start. It never addresses the person.
        let banned = [
            "adhd", "anxiety", "anxious", "depress", "executive dysfunction",
            "disorder", "diagnos", "symptom", "therapy", "condition", "your brain"
        ]

        for line in allRescueCopy() {
            let lowered = line.lowercased()
            for word in banned {
                #expect(!lowered.contains(word), "'\(word)' appears in: \(line)")
            }
        }
    }

    @Test("nothing Rescue says raises the deadline")
    func neverInvokesTheDeadline() {
        // Pressure is what sent the user here. Rescue's job is to make the next movement
        // smaller, and reminding someone of a due date does the opposite.
        for line in allRescueCopy() {
            let lowered = line.lowercased()
            for word in ["overdue", "deadline", "due ", "urgent", "hurry", "running out"] {
                #expect(!lowered.contains(word), "'\(word)' appears in: \(line)")
            }
        }
    }

    @Test("Rescue is written flat: no exclamation, no emoji")
    func staysFlat() {
        for line in allRescueCopy() {
            #expect(!line.contains("!"), "exclamation in: \(line)")
            #expect(
                line.unicodeScalars.allSatisfy { $0.value < 0x2000 },
                "non-plain character in: \(line)"
            )
        }
    }
}

@Suite("Rescue — never a chatbot")
struct RescueContainmentTests {

    @Test("there are exactly four ways in, and each is a fixed question")
    func fourFixedPaths() {
        // PRODUCT_SPEC.md §4.11: Rescue must never degrade into an open chatbot. A fifth
        // free-text path would be a product defect, so the count is asserted, not assumed.
        #expect(RescuePath.allCases.count == 4)

        let prompts = RescuePath.allCases.map(\.prompt)
        #expect(Set(prompts).count == 4)
        #expect(prompts.allSatisfy { !$0.isEmpty })
    }

    @Test("only one path asks the user anything before it answers")
    func onlyOnePathAsksAQuestion() {
        #expect(RescuePath.allCases.filter(\.needsTimeBudget) == [.notEnoughTime])
    }

    @Test("every answer is one framing line and exactly one action")
    func everyAnswerIsTwoLines() {
        let rescue = RescueStrategy()
        let task = makeTask(id: "essay", title: "Finish history essay")
        let child = makeTask(id: "c", title: "Find one source", parentID: TaskID("essay"))
        let all = [task, child]

        var responses = [
            rescue.dontKnowHowToStart(with: task, among: all),
            rescue.dontKnowHowToStart(with: task, among: all, stepsAlreadyRevealed: 1),
            rescue.tooMuch(with: task, among: all),
            rescue.dontWantTo(with: task, among: all)
        ]
        if let timed = rescue.notEnoughTime(.thirty, from: all, now: .testReference).response {
            responses.append(timed)
        }

        for response in responses {
            #expect(response.lines.count == 2, "\(response.path) returned \(response.lines)")
            #expect(response.lines.allSatisfy { !$0.isEmpty })
        }
    }
}
