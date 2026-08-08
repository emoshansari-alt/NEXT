import Foundation
import Testing

@testable import NextKit

// The provider that works on a train.
//
// No model, no network, no key, no consent prompt. PRODUCT_SPEC.md §6 requires NEXT to stay
// genuinely useful when the provider is down, the user declined, or the hardware cannot run a
// model at all, and this is the thing that makes that true rather than aspirational.
//
// Its defining property is not cleverness. It is that it never guesses: a date it recognises
// comes back flagged for confirmation, and a date it does not recognise comes back as no date
// at all.

private let fallback = TemplateFallbackProvider()

private func extract(
    _ text: String,
    now: Date = .testReference
) async throws -> Validated<TaskExtraction> {
    try await fallback.extractTasks(
        TaskExtractionRequest(text: text, now: now, timeZone: testTimeZone)
    )
}

@Suite("TemplateFallbackProvider — a student's brain dump")
struct TemplateFallbackExtractionTests {

    /// The example from PRODUCT_SPEC.md §4.5, verbatim.
    private let specDump = "chem test monday, finish history slides friday, email professor, practice at 6"

    @Test("the spec's brain dump becomes four separate tasks")
    func specDumpSplitsIntoFour() async throws {
        let validated = try await extract(specDump)

        #expect(validated.value.tasks.map(\.title) == [
            "Chem test",
            "Finish history slides",
            "Email professor",
            "Practice at 6"
        ])
    }

    @Test("the dates it recognises are attached to the right tasks")
    func specDumpDates() async throws {
        let validated = try await extract(specDump)
        let tasks = validated.value.tasks

        #expect(tasks[0].deadline?.date == iso("2026-03-16T23:59:00Z"))
        #expect(tasks[1].deadline?.date == iso("2026-03-13T23:59:00Z"))
    }

    @Test("the dates it cannot recognise are absent, not invented")
    func specDumpLeavesUnknownDatesAlone() async throws {
        // "email professor" has no date in it, and "practice at 6" has a time with no day.
        // Neither becomes a deadline. This is the whole discipline of the module in two rows.
        let validated = try await extract(specDump)
        let tasks = validated.value.tasks

        #expect(tasks[2].deadline == nil)
        #expect(tasks[3].deadline == nil)
    }

    @Test("every recognised date is put to the user rather than written silently")
    func recognisedDatesAreConfirmed() async throws {
        let validated = try await extract(specDump)

        #expect(
            validated.confirmations.map { "\($0.itemIndex):\($0.field.rawValue)" }
                == ["0:deadline", "1:deadline"]
        )
    }

    @Test("nothing the fallback produces reaches the database with a guessed deadline")
    func noGuessedDeadlineIsWritten() async throws {
        let validated = try await extract(specDump)

        let items = validated.taskItems(
            idProvider: SequentialIDs(), createdAt: .testReference
        )

        #expect(items.count == 4)
        #expect(items.allSatisfy { $0.deadline == nil })
        #expect(items.map(\.title) == validated.value.tasks.map(\.title))
    }

    @Test("the Capture Confirmation example from the spec splits on \"and\"")
    func captureConfirmationExample() async throws {
        // PRODUCT_SPEC.md §4.6: "chem thing thurs and paper next friday".
        let validated = try await extract("chem thing thurs and paper next friday")

        #expect(validated.value.tasks.map(\.title) == ["Chem thing", "Paper"])
        #expect(validated.value.tasks[0].deadline?.date == iso("2026-03-12T23:59:00Z"))
        #expect(validated.value.tasks[1].deadline?.date == iso("2026-03-13T23:59:00Z"))
    }

    @Test("a dump written as lines works as well as one written with commas")
    func newlineSeparatedDump() async throws {
        let validated = try await extract(
            """
            - Chemistry worksheet
            - Read chapter 4
            * Email Professor Hale
            1. Book a practice room
            """
        )

        #expect(validated.value.tasks.map(\.title) == [
            "Chemistry worksheet", "Read chapter 4", "Email Professor Hale",
            "Book a practice room"
        ])
    }

    @Test("importance is never inferred")
    func importanceIsNeverInferred() async throws {
        // Importance is the user's judgement about their own work. "URGENT!!! chem test" is the
        // user shouting at themselves, not a field NEXT gets to fill in.
        let validated = try await extract("URGENT chem test monday, important essay")

        #expect(validated.value.tasks.allSatisfy { $0.importance == .normal })
    }

    @Test("duration is never inferred")
    func durationIsNeverInferred() async throws {
        let validated = try await extract("chem test monday, 20 minute reading")

        #expect(validated.value.tasks.allSatisfy { $0.duration == nil })
    }

    @Test("the title is the user's own words, tidied and nothing more")
    func titlesAreTheUsersWords() async throws {
        let validated = try await extract("finish the stupid history slides friday")

        #expect(validated.value.tasks.map(\.title) == ["Finish the stupid history slides"])
    }

    @Test("a single task with no punctuation at all still works")
    func singleFragment() async throws {
        let validated = try await extract("email professor")

        #expect(validated.value.tasks.map(\.title) == ["Email professor"])
    }

    @Test("\"and\" inside a phrase does not split it")
    func andInsideAPhraseIsLeftAlone() async throws {
        // Splitting on every "and" would turn "black and white photos" into two tasks.
        let validated = try await extract("print the black and white photos")

        #expect(validated.value.tasks.map(\.title) == ["Print the black and white photos"])
    }

    @Test("an undated \"and\" is left joined rather than guessed apart")
    func undatedAndIsLeftJoined() async throws {
        // This really is two things, and NEXT does not split it, because the same rule that
        // would split it here would wreck "black and white photos" over there. One task holding
        // two obligations is usable and honest; two broken half-tasks are neither. The user is
        // looking at this on the Capture Confirmation screen and can split it themselves.
        let validated = try await extract("email professor and book a practice room")

        #expect(
            validated.value.tasks.map(\.title) == ["Email professor and book a practice room"]
        )
    }

    @Test("a dump pasted as sentences is separated, not merged and edited")
    func fullStopsSeparate() async throws {
        // Pasting from Notes or a message is an ordinary way to capture, and it arrives
        // punctuated. Without the full stop as a separator these two obligations become one
        // task — and worse, the date parser then lifts "monday" out of the middle of it, so the
        // user is shown a sentence they did not write with a word missing from it.
        let validated = try await extract("Chem test monday. Email professor.")

        #expect(validated.value.tasks.map(\.title) == ["Chem test", "Email professor."])
        #expect(validated.value.tasks[0].deadline?.date == iso("2026-03-16T23:59:00Z"))
        #expect(validated.value.tasks[1].deadline == nil)
    }

    @Test("a standing commitment does not manufacture a task named after a weekday")
    func recurringWeekdayPairIsNotSplit() async throws {
        // "practice mon and wed" is one commitment written the way students write them. Cut on
        // the "and", the right-hand side is nothing but "wed" — a fragment the parser will not
        // strip, because doing so would leave a nameless row — so it arrives as a task called
        // "Wed" with no deadline, invented out of half a sentence.
        //
        // The conjunction is still in the title, because "mon" is the phrase that was read and
        // turned into the deadline. One task the user can edit in place beats one task plus a
        // phantom they have to hunt down and delete.
        for text in ["practice mon and wed", "gym tuesday and thursday"] {
            let validated = try await extract(text)
            #expect(validated.value.tasks.count == 1, "\(text)")
        }

        #expect(
            try await extract("practice mon and wed").value.tasks.map(\.title)
                == ["Practice and wed"]
        )
        #expect(
            try await extract("gym tuesday and thursday").value.tasks[0].deadline?.date
                == iso("2026-03-17T23:59:00Z")
        )
    }

    @Test("empty input is refused rather than producing an empty capture")
    func emptyInputIsRefused() async throws {
        for text in ["", "   ", "\n\n", ",,,", " , , "] {
            await #expect(
                throws: IntelligenceError.validationFailed(.emptyResponse(.extractTasks)),
                "accepted: '\(text)'"
            ) {
                _ = try await extract(text)
            }
        }
    }

    @Test("the fallback's own output still has to pass the gate")
    func fallbackOutputIsValidatedToo() async throws {
        // The deterministic provider is not exempt. A pasted paragraph produces a fragment
        // longer than a title is allowed to be, and the honest answer is to refuse rather than
        // to truncate the user's own words — manual entry is always available (§4.5).
        let paragraph = String(repeating: "a", count: ValidationLimits.default.maxTitleLength + 1)

        await #expect(throws: IntelligenceError.self) {
            _ = try await extract(paragraph)
        }
    }

    @Test("a dump larger than the response limit is refused whole")
    func oversizedDumpIsRefused() async throws {
        let limit = ValidationLimits.default.maxTasksPerResponse
        let text = (0...limit).map { "task \($0)" }.joined(separator: ", ")

        await #expect(
            throws: IntelligenceError.validationFailed(
                .tooManyItems(.extractTasks, count: limit + 1, limit: limit)
            )
        ) {
            _ = try await extract(text)
        }
    }

    @Test("the same dump extracted twice gives the same tasks")
    func extractionIsDeterministic() async throws {
        let first = try await extract(specDump)
        let second = try await extract(specDump)

        #expect(first == second)
    }
}

@Suite("TemplateFallbackProvider — steps without a model")
struct TemplateFallbackStepTests {

    @Test("a decomposition comes from the work the title describes")
    func decompositionUsesWorkKind() async throws {
        let validated = try await fallback.decompose(
            DecompositionRequest(title: "Finish history essay", estimatedMinutes: 90, maxSteps: 6)
        )

        #expect(validated.value.steps.map(\.text) == WorkKind.writing.firstSteps)
    }

    @Test("a decomposition never exceeds the number of steps asked for")
    func decompositionRespectsMaxSteps() async throws {
        let validated = try await fallback.decompose(
            DecompositionRequest(title: "Finish history essay", estimatedMinutes: nil, maxSteps: 2)
        )

        #expect(validated.value.steps.count == 2)
        #expect(validated.value.steps.map(\.text) == Array(WorkKind.writing.firstSteps.prefix(2)))
    }

    @Test("a title that says nothing gets the honest generic ladder")
    func unrecognisedTitleFallsBackToGeneric() async throws {
        let validated = try await fallback.decompose(
            DecompositionRequest(title: "Sort out the thing", estimatedMinutes: nil, maxSteps: 6)
        )

        #expect(validated.value.steps.map(\.text) == StepShrinker.genericSteps.map(\.text))
    }

    @Test("a guessed ladder is trusted less than a recognised one")
    func genericLadderIsLessConfident() async throws {
        let recognised = try await fallback.decompose(
            DecompositionRequest(title: "Chemistry worksheet", estimatedMinutes: nil, maxSteps: 3)
        )
        let guessed = try await fallback.decompose(
            DecompositionRequest(title: "Sort out the thing", estimatedMinutes: nil, maxSteps: 3)
        )

        #expect(guessed.value.steps[0].confidence < recognised.value.steps[0].confidence)
        #expect(!recognised.requiresConfirmation)
        #expect(guessed.requiresConfirmation)
    }

    @Test("a next action is the first rung of the same ladder")
    func nextActionIsTheFirstRung() async throws {
        let validated = try await fallback.nextAction(
            NextActionRequest(title: "Chemistry worksheet")
        )

        #expect(validated.value.text == WorkKind.problemSet.firstSteps[0])
    }

    @Test("a next action is always a physical action, for every kind of work NEXT knows")
    func everyWorkKindProducesAStep() async throws {
        for kind in WorkKind.allCases {
            for keyword in kind.objects.union(kind.verbs) {
                let validated = try await fallback.nextAction(
                    NextActionRequest(title: "do the \(keyword)")
                )
                #expect(!validated.value.text.isEmpty, "\(keyword)")
            }
        }
    }

    @Test("Rescue gets a step, and never gets a voice")
    func simplifyReturnsAStepOnly() async throws {
        let validated = try await fallback.simplify(
            SimplificationRequest(title: "Finish history essay", path: .tooMuch)
        )

        #expect(validated.value.text == WorkKind.writing.firstSteps[0])
    }

    @Test("the four Rescue paths get the same step, because the difference is framing")
    func everyPathGetsTheSameStep() async throws {
        // The four paths differ in what is *said around* the step — "Start here.", "Forget the
        // rest of it for now." — and that copy is generated by `RescueFraming`, deterministically
        // and in NEXT's own voice. A provider is never asked for it, so this layer has nothing
        // path-specific to offer and does not pretend otherwise.
        var steps: Set<String> = []
        for path in RescuePath.allCases {
            let validated = try await fallback.simplify(
                SimplificationRequest(title: "Finish history essay", path: path)
            )
            steps.insert(validated.value.text)
        }

        #expect(steps.count == 1)
    }
}

@Suite("TemplateFallbackProvider — what it will not do")
struct TemplateFallbackLimitsTests {

    @Test("it declines to estimate a duration rather than making a number up")
    func durationEstimationIsUnsupported() async throws {
        // There is no deterministic answer to "how long will this take". Guessing would poison
        // the time-budget filter, Focus and Minimum Win at once, and an unestimated task is
        // already handled honestly everywhere: unknown duration means "might fit", not "does
        // not fit" (see `TaskItem.estimatedMinutes`).
        await #expect(throws: IntelligenceError.unsupported(.estimateDuration)) {
            _ = try await fallback.estimateDuration(
                DurationEstimateRequest(title: "Finish history essay")
            )
        }
    }

    @Test("it says up front which operations it can answer")
    func supportedOperationsAreHonest() {
        // Stated by exclusion, because that is the actual product statement: four of the five,
        // and not the one there is no honest deterministic answer to. Comparing the set to
        // `[.extractTasks, .decompose, .nextAction, .simplify]` would be quoting the
        // implementation's own literal back at it, which agrees with any change made to both.
        #expect(!fallback.supports(.estimateDuration))

        #expect(fallback.supports(.extractTasks))
        #expect(fallback.supports(.decompose))
        #expect(fallback.supports(.nextAction))
        #expect(fallback.supports(.simplify))
        #expect(fallback.supportedOperations.count == 4)
    }

    @Test("it is available with no network, no key and no consent")
    func noConfigurationIsRequired() async throws {
        // Constructed with nothing, answering immediately. If this test ever needs a setup step,
        // the offline guarantee has quietly stopped being one.
        let bare = TemplateFallbackProvider()

        let validated = try await bare.nextAction(NextActionRequest(title: "Chemistry worksheet"))

        #expect(!validated.value.text.isEmpty)
    }
}

@Suite("Brain dump splitting")
struct BrainDumpSplitterTests {

    @Test("commas, semicolons and newlines all separate")
    func separators() {
        #expect(
            BrainDumpSplitter.fragments(in: "a task; another task, a third\na fourth")
                == ["a task", "another task", "a third", "a fourth"]
        )
    }

    @Test("list markers are stripped")
    func listMarkers() {
        #expect(
            BrainDumpSplitter.fragments(in: "- one\n* two\n• three\n1. four\n2) five")
                == ["one", "two", "three", "four", "five"]
        )
    }

    @Test("empty pieces are dropped rather than becoming blank tasks")
    func emptyPiecesDropped() {
        #expect(BrainDumpSplitter.fragments(in: "one,,  ,two,") == ["one", "two"])
    }

    @Test("\"and\" splits only when each side carries its own date")
    func andSplitsOnlyWithADateOnBothSides() {
        #expect(
            BrainDumpSplitter.fragments(in: "chem thing thurs and paper next friday")
                == ["chem thing thurs", "paper next friday"]
        )
        #expect(
            BrainDumpSplitter.fragments(in: "black and white photos")
                == ["black and white photos"]
        )
        #expect(BrainDumpSplitter.fragments(in: "essay and") == ["essay and"])
    }

    @Test("one date between them is not enough to cut a phrase in half")
    func oneSidedDateDoesNotSplit() {
        // The trap this rule exists for. "friday" belongs to the photos, not to a second task
        // called "black".
        #expect(
            BrainDumpSplitter.fragments(in: "print the black and white photos by friday")
                == ["print the black and white photos by friday"]
        )
    }

    @Test("a side that is nothing but a date is not a second task")
    func dateOnlySideDoesNotSplit() {
        // "practice mon and wed" is how a student writes a standing commitment, not two things.
        // Cutting it leaves a right-hand side with no words of its own, and a fragment that is
        // only a weekday cannot be given a name — so the split manufactures a task called "Wed"
        // that the user never wrote and now has to delete.
        #expect(
            BrainDumpSplitter.fragments(in: "practice mon and wed") == ["practice mon and wed"]
        )
        #expect(
            BrainDumpSplitter.fragments(in: "gym tuesday and thursday")
                == ["gym tuesday and thursday"]
        )
        #expect(
            BrainDumpSplitter.fragments(in: "monday and chem test friday")
                == ["monday and chem test friday"]
        )
    }

    @Test("a full stop between sentences separates; one inside a word or a marker does not")
    func fullStopSeparates() {
        #expect(
            BrainDumpSplitter.fragments(in: "Chem test monday. Email professor.")
                == ["Chem test monday", "Email professor."]
        )
        // A numbered marker, a chapter number and an initial all end in a full stop and none of
        // them ends a sentence. Cutting at one produces a task called "1", which is exactly the
        // kind of debris this splitter exists to avoid.
        #expect(BrainDumpSplitter.fragments(in: "1. Book a practice room") == ["Book a practice room"])
        #expect(BrainDumpSplitter.fragments(in: "read chapter 3. and take notes") == ["read chapter 3. and take notes"])
        #expect(BrainDumpSplitter.fragments(in: "email Prof. Hale") == ["email Prof. Hale"])
        #expect(BrainDumpSplitter.fragments(in: "find the J. K. Rowling essay") == ["find the J. K. Rowling essay"])
        #expect(BrainDumpSplitter.fragments(in: "book a 1.5 hour room") == ["book a 1.5 hour room"])
    }

    @Test("a chain of dated items splits all the way along")
    func chainedAndsSplit() {
        #expect(
            BrainDumpSplitter.fragments(in: "gym monday and chem tuesday and essay friday")
                == ["gym monday", "chem tuesday", "essay friday"]
        )
    }

    @Test("the spec's dump always splits into exactly these fragments")
    func splittingIsDeterministic() {
        // Determinism is pinned by naming the answer, not by comparing a pure function to
        // itself. `fragments(in:) == fragments(in:)` holds for any implementation whatsoever,
        // including one that returned nothing, so it could never have gone red.
        //
        // The dump is PRODUCT_SPEC.md §4.5, verbatim. Fragments, not titles: the date phrases
        // are still in them, because removing those is `DatePhraseParser`'s job and not this
        // type's.
        #expect(
            BrainDumpSplitter.fragments(
                in: "chem test monday, finish history slides friday, email professor, practice at 6"
            ) == [
                "chem test monday",
                "finish history slides friday",
                "email professor",
                "practice at 6"
            ]
        )
    }
}
