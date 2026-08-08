import Foundation
import Testing

@testable import NextKit

// Minimum Win is the single most dangerous surface in NEXT.
//
// It is reached by a student who cannot finish something that is due, which is precisely the
// moment a productivity app is tempted to (a) tell them whose fault that is, and (b) offer a
// shortcut that is really a cheat. PRODUCT_SPEC.md forbids both outright: §1 draws the
// academic-integrity boundary, invariant P5 forbids productivity morality.
//
// These sweeps run over every string the module can produce, so a well-meaning future edit to
// any one line trips them.

private let planner = MinimumWinPlanner()

private let everyKind: [WorkKind?] = [nil] + WorkKind.allCases.map { $0 }

/// Every stage instruction the module can render, for every kind of work.
private func allStageInstructions() -> [String] {
    MinimumWinStage.allCases.flatMap { stage in
        everyKind.map { stage.instruction(for: $0) }
    }
}

// MARK: - The reviewed table
//
// Every line Minimum Win can put in front of a student when the task says nothing about its own
// shape: nine kinds of work — the eight NEXT recognises plus the one it does not — times three
// stages. Twenty-seven strings, written out here as literals.
//
// They are literals on purpose, and this is the whole point of the file. A table built by
// calling `MinimumWinStage.instruction(for:)` — the same function the planner calls — turns
// every assertion below into `implementation == implementation`, which no edit to the copy can
// ever break. That hole was real: an outright invitation to submit another student's outline
// sat in the shipping writing ladder and the entire suite, academic-integrity sweep included,
// stayed green. Pinning the copy means changing a line NEXT says to a student is a red suite,
// and a red suite is a human re-reading the new wording before it ships (PRODUCT_SPEC.md §1).
//
// So: if this table sent you here, do not sync it to the implementation. Read the new line and
// decide whether NEXT should be saying it.

/// The three reviewed lines for one kind of work, in stage order.
private struct ReviewedLadder {
    let kind: WorkKind?
    let outline: String
    let opening: String
    let firstPart: String

    func line(for stage: MinimumWinStage) -> String {
        switch stage {
        case .outline: outline
        case .opening: opening
        case .firstPart: firstPart
        }
    }
}

private let reviewedLadders: [ReviewedLadder] = [
    ReviewedLadder(
        kind: nil,
        outline: "Find the instructions and write down what this has to produce.",
        opening: "Do the first item on that list.",
        firstPart: "Do the next item on that list."
    ),
    ReviewedLadder(
        kind: .writing,
        outline: "Write a bare outline: your points, in the order you will make them.",
        opening: "Write the introduction.",
        firstPart: "Write the first section in full."
    ),
    ReviewedLadder(
        kind: .reading,
        outline: "Skim the headings and write down what the text covers.",
        opening: "Read the first section.",
        firstPart: "Write three lines on what that section said."
    ),
    ReviewedLadder(
        kind: .problemSet,
        outline: "Read every question and mark the ones you can already do.",
        opening: "Answer the first question you marked.",
        firstPart: "Answer the rest of the ones you marked."
    ),
    ReviewedLadder(
        kind: .presentation,
        outline: "List the three points the talk has to make.",
        opening: "Make a title slide and one slide per point.",
        firstPart: "Fill in the first point's slide properly."
    ),
    ReviewedLadder(
        kind: .revision,
        outline: "List the topics it covers and mark the ones you have not gone over.",
        opening: "Read your notes on the first topic you marked.",
        firstPart: "Cover the page and write down what you remember of it."
    ),
    ReviewedLadder(
        kind: .practice,
        outline: "Set out what you need and pick the one section to work on.",
        opening: "Run that section once, slowly.",
        firstPart: "Repeat that section until it is clean."
    ),
    ReviewedLadder(
        kind: .correspondence,
        outline: "Write down the one thing you need from them.",
        opening: "Open a message and fill in the recipient and the subject.",
        firstPart: "Write the message in your own words and send it."
    ),
    ReviewedLadder(
        kind: .admin,
        outline: "Open the form and read what it asks for.",
        opening: "Fill in every field you already have to hand.",
        firstPart: "Track down the one missing detail and finish the form."
    )
]

/// The reviewed table, flattened. The only definition of "a line a human has signed off".
private let reviewedStageLines: [String] = reviewedLadders.flatMap {
    [$0.outline, $0.opening, $0.firstPart]
}

/// Plans covering each kind of work at several sizes of window, so the assembled output is
/// checked as it is actually read rather than only in pieces.
private func allGeneratedPlans() -> [MinimumWinPlan] {
    let titles = [
        "Zzyzx",                       // nothing inferable
        "History paper",               // writing
        "Read chapter four",           // reading
        "Chemistry worksheet",         // problem set
        "Biology slides",              // presentation
        "Study for the physics test",  // revision
        "Piano practice",              // practice
        "Email Professor Hale",        // correspondence
        "Submit the enrolment form"    // admin
    ]

    return titles.flatMap { title in
        [0.2, 1, 3, 5].compactMap { hours -> MinimumWinPlan? in
            let task = makeTask(
                id: "t",
                title: title,
                deadline: .hoursFromReference(hours),
                estimatedMinutes: 360
            )
            return planner.plan(for: task, now: .testReference).plan
        }
    }
}

/// Every line the module can put in front of a user, independent of their own words.
private func allMinimumWinCopy() -> [String] {
    var copy = allStageInstructions()

    for minutes in [1, 5, 30, 120, 300] {
        copy.append(MinimumWinFraming.hereIsWhatFits(minutesRemaining: minutes).sentence)
        copy.append(MinimumWinFraming.onlyAStartFits(minutesRemaining: minutes).sentence)
    }

    for plan in allGeneratedPlans() {
        copy.append(plan.framing.sentence)
        copy += plan.rungs.flatMap { $0.steps.map(\.text) }
    }

    return copy
}

@Suite("Minimum Win — the reviewed stage copy")
struct MinimumWinStageCopyTests {

    @Test("the table covers every kind of work exactly once")
    func tableIsComplete() {
        // A kind missing from the table would be a kind whose copy nothing pins, which is the
        // same hole in a smaller shape.
        #expect(reviewedLadders.count == everyKind.count)
        #expect(Set(reviewedLadders.map(\.kind)) == Set(everyKind))
        #expect(reviewedStageLines.count == 27)
    }

    @Test("each stage of each kind renders its reviewed line, word for word")
    func everyLineMatchesTheReviewedCopy() {
        for ladder in reviewedLadders {
            for stage in MinimumWinStage.allCases {
                #expect(
                    stage.instruction(for: ladder.kind) == ladder.line(for: stage),
                    """
                    Stage copy changed — \(String(describing: ladder.kind)) / \(stage).
                      reviewed: \(ladder.line(for: stage))
                       shipping: \(stage.instruction(for: ladder.kind))
                    Read the new line against PRODUCT_SPEC.md §1 and §3 before updating the \
                    table.
                    """
                )
            }
        }
    }

    @Test("the module can render nothing outside the reviewed table")
    func nothingElseIsRenderable() {
        // Sorted rather than set-compared, so a line quietly duplicated across two kinds — or
        // one dropped — shows up as well as one reworded.
        #expect(allStageInstructions().sorted() == reviewedStageLines.sorted())
    }
}

@Suite("Minimum Win — academic integrity")
struct MinimumWinIntegrityTests {

    @Test("no suggestion is a way of not doing the work")
    func neverSuggestsDishonesty() {
        // PRODUCT_SPEC.md §1: NEXT assists with action, not with producing submittable work.
        // A reduced goal must be a smaller amount of the user's own work — never the same
        // amount of work done by somebody or something else, and never less work disguised as
        // the same amount.
        let banned = [
            "fabricat", "invent", "make up", "made up", "made-up",
            "plagiar", "copy", "paste", "lift ", "borrow",
            "pad ", "padding", "filler", "waffle", "bluff", "fluff",
            "fake", "pretend", "hand it in as", "pass it off", "claim you",
            "say you", "someone else", "somebody else", "another student",
            "generate", "chatgpt", "ai to", "have it written",
            "cite anything", "without reading", "skip the reading",
            "guess the answer", "round up your", "exaggerat"
        ]

        for line in allMinimumWinCopy() {
            let lowered = line.lowercased()
            for phrase in banned {
                #expect(!lowered.contains(phrase), "'\(phrase)' appears in: \(line)")
            }
        }
    }

    @Test("a step is either the user's own words or one of the reviewed stage lines")
    func stepsAreNeverImprovised() {
        // The structural half of the integrity guarantee, and the stronger half. Every rung
        // is traceable: it is either something the user wrote, or one of a fixed table of
        // lines that a human reviewed. Nothing in this module composes new instructions, so
        // there is no path by which it can start suggesting content for the work itself.
        //
        // "Reviewed" means the literal table above, not whatever the module currently returns.
        // Asking the implementation what it says and then checking it said that is not a check.
        let reviewed = Set(reviewedStageLines)

        let parent = makeTask(
            id: "paper",
            title: "History paper",
            deadline: .hoursFromReference(4),
            estimatedMinutes: 360
        )
        let children = [
            makeTask(
                id: "a",
                title: "Find three sources",
                estimatedMinutes: 40,
                parentID: TaskID("paper"),
                createdAt: .hoursFromReference(-2)
            ),
            makeTask(
                id: "b",
                title: "Outline",
                estimatedMinutes: 30,
                nextAction: "Sketch the three arguments in order",
                parentID: TaskID("paper"),
                createdAt: .hoursFromReference(-1)
            )
        ]
        let byID = Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0) })

        var plans = allGeneratedPlans()
        let decomposed = planner.plan(
            for: parent,
            among: [parent] + children,
            now: .testReference
        )
        if let decomposed = decomposed.plan {
            plans.append(decomposed)
        }

        for plan in plans {
            for step in plan.rungs.flatMap(\.steps) {
                switch step.origin {
                case .stage:
                    #expect(reviewed.contains(step.text), "unreviewed line: \(step.text)")

                case .substep(let id):
                    guard let child = byID[id] else {
                        Issue.record("step cites an unknown substep: \(id)")
                        continue
                    }
                    let theirWords = [
                        StepShrinker.instruction(from: child.nextAction),
                        StepShrinker.instruction(from: child.title)
                    ].compactMap { $0 }
                    #expect(theirWords.contains(step.text), "reworded the user: \(step.text)")
                }
            }
        }
    }

    @Test("a rung that cannot finish says so instead of implying it can")
    func aPartialIsLabelledAPartial() {
        // Twelve minutes against six hours. The honest offer is the twelve minutes, clearly
        // marked as not reaching the goal. Presenting it as a completed outcome would be the
        // app misrepresenting the state of the user's work to the user.
        let task = makeTask(
            id: "paper",
            title: "History paper",
            deadline: .hoursFromReference(0.2),
            estimatedMinutes: 360
        )
        guard let plan = planner.plan(for: task, now: .testReference).plan else {
            Issue.record("expected a ladder")
            return
        }
        #expect(plan.best.isTimeBoxed)
        #expect(plan.best.minutes < plan.best.goal.minutes)
        #expect(plan.framing == .onlyAStartFits(minutesRemaining: plan.minutesRemaining))
    }
}

@Suite("Minimum Win — tone")
struct MinimumWinToneTests {

    @Test("nothing implies the user has fallen short")
    func neverShames() {
        // Invariant P5. The user is looking at this screen because time ran out; they do not
        // need it explained to them, and explaining it does not produce a page of the paper.
        let banned = [
            "failed", "fail", "behind", "streak", "again", "still haven't", "lazy",
            "should have", "you didn't", "you never", "miss you", "wasted",
            "procrastinat", "excuse", "give up", "slack", "too late", "ran out",
            "out of time", "no point", "salvage", "damage", "at least"
        ]

        for line in allMinimumWinCopy() {
            let lowered = line.lowercased()
            for word in banned {
                #expect(!lowered.contains(word), "'\(word)' appears in: \(line)")
            }
        }
    }

    @Test("nothing is a pep talk")
    func neverMotivates() {
        let banned = [
            "you've got this", "you can do it", "amazing", "great job", "well done",
            "keep it up", "proud", "believe in", "crush it", "smash it",
            "motivat", "willpower", "discipline", "champion", "journey", "don't worry"
        ]

        for line in allMinimumWinCopy() {
            let lowered = line.lowercased()
            for word in banned {
                #expect(!lowered.contains(word), "'\(word)' appears in: \(line)")
            }
        }
    }

    @Test("nothing frames the user as having a condition")
    func neverDiagnoses() {
        let banned = [
            "adhd", "anxiety", "anxious", "depress", "executive dysfunction",
            "disorder", "diagnos", "symptom", "therapy", "condition", "your brain",
            "overwhelm", "panic", "stress"
        ]

        for line in allMinimumWinCopy() {
            let lowered = line.lowercased()
            for word in banned {
                #expect(!lowered.contains(word), "'\(word)' appears in: \(line)")
            }
        }
    }

    @Test("Minimum Win is written flat: no exclamation, no emoji")
    func staysFlat() {
        for line in allMinimumWinCopy() {
            #expect(!line.contains("!"), "exclamation in: \(line)")
            #expect(
                line.unicodeScalars.allSatisfy { $0.value < 0x2000 },
                "non-plain character in: \(line)"
            )
            #expect(!line.isEmpty)
        }
    }

    @Test("the framing states the time and then points at the list")
    func framingIsAFactAndAPointer() {
        // "You have two hours left, here is what fits" — the whole tone of the feature in one
        // line. It says what is true and then gets out of the way.
        #expect(
            MinimumWinFraming.hereIsWhatFits(minutesRemaining: 120).sentence
                == "You have 2 hours left. Here is what fits."
        )
        #expect(
            MinimumWinFraming.onlyAStartFits(minutesRemaining: 12).sentence
                == "You have 12 minutes left. This is where to spend it."
        )
    }
}
