import Foundation
import Testing

@testable import NextKit

// The validator is the boundary between something NEXT did not write and the user's task
// database. PRODUCT_SPEC.md §6: "No AI response can corrupt the local task database."
//
// These tests are written from the outside in — raw bytes go in, and either a validated value
// or a named rejection comes out. Nothing here constructs a `Validated` value directly, because
// nothing *can*: its initialiser is private to `ResponseValidator.swift`, so the gate is
// structural rather than a convention callers are trusted to follow.

@Suite("ResponseValidator — a well-formed response")
struct ResponseValidatorHappyPathTests {

    @Test("a well-formed extraction yields its tasks")
    func wellFormedExtractionValidates() throws {
        let validated = try validateExtraction(
            extractionJSON(taskJSON(title: "Chemistry worksheet"))
        )

        #expect(validated.value.tasks.count == 1)
        #expect(validated.value.tasks[0].title == "Chemistry worksheet")
    }

    @Test("the shape the product spec illustrates validates exactly as written")
    func specExampleValidates() throws {
        // Copied from PRODUCT_SPEC.md §6. If the validator ever stops accepting the documented
        // shape, either the validator or the spec is wrong and someone has to choose.
        let json = """
        {
          "tasks": [
            {
              "title": "Chemistry worksheet",
              "deadline": "2026-08-13T23:59:00Z",
              "estimatedMinutes": 30,
              "importance": "normal",
              "confidence": { "title": 0.97, "deadline": 0.72 }
            }
          ]
        }
        """

        let validated = try validateExtraction(json)
        let task = try #require(validated.value.tasks.first)

        #expect(task.title == "Chemistry worksheet")
        #expect(task.deadline?.date == iso("2026-08-13T23:59:00Z"))
        #expect(task.duration?.minutes == 30)
        #expect(task.importance == .normal)
        #expect(task.titleConfidence.value == 0.97)

        // The example states 0.72 for the deadline and says nothing at all about the duration.
        // Both are below the bar to act on unasked, so both are questions rather than writes.
        #expect(validated.confirmations.map(\.field) == [.deadline, .estimatedMinutes])
    }

    @Test("an absent importance means normal rather than a rejection")
    func absentImportanceDefaultsToNormal() throws {
        let validated = try validateExtraction(extractionJSON(taskJSON(importance: nil)))

        #expect(validated.value.tasks[0].importance == .normal)
    }

    @Test("importance is matched case- and whitespace-insensitively")
    func importanceIsMatchedLeniently() throws {
        let validated = try validateExtraction(
            extractionJSON(taskJSON(importance: "  Important "))
        )

        #expect(validated.value.tasks[0].importance == .important)
    }

    @Test("a task with nothing but a title is a complete, valid task")
    func titleAloneIsEnough() throws {
        let validated = try validateExtraction(extractionJSON(taskJSON()))
        let task = try #require(validated.value.tasks.first)

        #expect(task.deadline == nil)
        #expect(task.duration == nil)
        #expect(validated.confirmations.isEmpty)
    }
}

@Suite("ResponseValidator — required fields")
struct ResponseValidatorRequiredFieldTests {

    @Test("a task with no title is rejected")
    func missingTitleIsRejected() throws {
        let failure = try #require(try extractionFailure(extractionJSON(taskJSON(title: nil))))

        #expect(failure == .missingRequiredField(.title, itemIndex: 0))
    }

    @Test("a whitespace-only title is treated as no title at all")
    func blankTitleIsRejected() throws {
        let failure = try #require(try extractionFailure(extractionJSON(taskJSON(title: "   \n"))))

        #expect(failure == .missingRequiredField(.title, itemIndex: 0))
    }

    @Test("a task with no confidence block is read as no confidence, not as certainty")
    func missingConfidenceIsUnstated() throws {
        // Silence is not a claim. A provider that omits confidence has not said the value is
        // right, so nothing here may be acted on without asking.
        let validated = try validateExtraction(extractionJSON(taskJSON(titleConfidence: nil)))

        #expect(validated.value.tasks[0].titleConfidence == .unstated)
        #expect(validated.confirmations.map(\.field) == [.title])
    }

    @Test("a deadline offered with no confidence for it is never written through")
    func deadlineWithoutItsConfidenceIsWithheld() throws {
        // This is the defect the module exists to prevent: a date arriving with no statement of
        // how sure anyone is would otherwise land in the database looking like a fact the user
        // stated. It is kept, and it is asked about.
        let validated = try validateExtraction(
            extractionJSON(taskJSON(deadline: "2026-03-13T23:59:00Z", deadlineConfidence: nil))
        )

        #expect(validated.value.tasks[0].deadline?.confidence == .unstated)
        #expect(validated.confirmations.map(\.field) == [.deadline])
        #expect(
            validated.taskItems(idProvider: SequentialIDs(), createdAt: .testReference)[0]
                .deadline == nil
        )
    }

    @Test("a duration offered with no confidence for it is never written through")
    func durationWithoutItsConfidenceIsWithheld() throws {
        let validated = try validateExtraction(
            extractionJSON(taskJSON(estimatedMinutes: 30, durationConfidence: nil))
        )

        #expect(validated.confirmations.map(\.field) == [.estimatedMinutes])
        #expect(
            validated.taskItems(idProvider: SequentialIDs(), createdAt: .testReference)[0]
                .estimatedMinutes == nil
        )
    }

    @Test("a response with no tasks key at all is rejected as empty")
    func absentTasksKeyIsEmpty() throws {
        let failure = try #require(try extractionFailure("{}"))

        #expect(failure == .emptyResponse(.extractTasks))
    }

    @Test("a response with an empty tasks array is rejected as empty")
    func emptyTasksArrayIsEmpty() throws {
        let failure = try #require(try extractionFailure("{ \"tasks\": [] }"))

        #expect(failure == .emptyResponse(.extractTasks))
    }
}

@Suite("ResponseValidator — bounded strings and counts")
struct ResponseValidatorBoundsTests {

    @Test("a title longer than the limit is rejected rather than truncated")
    func overlongTitleIsRejected() throws {
        // Truncating would silently rewrite what the user said. Rejecting sends them to manual
        // entry, which PRODUCT_SPEC.md §4.5 says is always available and never second-class.
        let limit = ValidationLimits.default.maxTitleLength
        let long = String(repeating: "a", count: limit + 1)

        let failure = try #require(try extractionFailure(extractionJSON(taskJSON(title: long))))

        #expect(
            failure == .fieldTooLong(.title, itemIndex: 0, length: limit + 1, limit: limit)
        )
    }

    @Test("a title exactly at the limit is accepted")
    func titleAtTheLimitIsAccepted() throws {
        let limit = ValidationLimits.default.maxTitleLength
        let exact = String(repeating: "a", count: limit)

        let validated = try validateExtraction(extractionJSON(taskJSON(title: exact)))

        #expect(validated.value.tasks[0].title.count == limit)
    }

    @Test("more tasks than the limit is rejected wholesale")
    func tooManyTasksIsRejected() throws {
        let limit = ValidationLimits.default.maxTasksPerResponse
        let tasks = (0...limit).map { taskJSON(title: "Task \($0)") }
        let json = "{ \"tasks\": [\(tasks.joined(separator: ", "))] }"

        let failure = try #require(try extractionFailure(json))

        #expect(failure == .tooManyItems(.extractTasks, count: limit + 1, limit: limit))
    }
}

@Suite("ResponseValidator — dates must be parseable and sane")
struct ResponseValidatorDateTests {

    @Test("the year 3000 is rejected as implausible")
    func distantFutureIsRejected() throws {
        let failure = try #require(
            try extractionFailure(
                extractionJSON(
                    taskJSON(deadline: "3000-01-01T00:00:00Z", deadlineConfidence: 0.9)
                )
            )
        )

        #expect(failure == .implausibleDate(.deadline, itemIndex: 0))
    }

    @Test("a date in the distant past is rejected as implausible")
    func distantPastIsRejected() throws {
        let failure = try #require(
            try extractionFailure(
                extractionJSON(
                    taskJSON(deadline: "1970-01-01T00:00:00Z", deadlineConfidence: 0.9)
                )
            )
        )

        #expect(failure == .implausibleDate(.deadline, itemIndex: 0))
    }

    @Test("a deadline that has just passed is accepted, because overdue is a normal state")
    func recentlyPastDeadlineIsAccepted() throws {
        // Invariant P4. An overdue task is the most ordinary thing a student has; treating a
        // past deadline as corrupt data would delete real work.
        let yesterday = "2026-03-09T17:00:00Z"

        let validated = try validateExtraction(
            extractionJSON(taskJSON(deadline: yesterday, deadlineConfidence: 0.9))
        )

        #expect(validated.value.tasks[0].deadline?.date == iso(yesterday))
    }

    @Test("a deadline that is not a date at all is rejected")
    func unparseableDateIsRejected() throws {
        let failure = try #require(
            try extractionFailure(
                extractionJSON(taskJSON(deadline: "sometime next week", deadlineConfidence: 0.9))
            )
        )

        #expect(failure == .unparseableDate(.deadline, itemIndex: 0))
    }

    @Test("a date-only string is accepted and lands at the start of that day")
    func dateOnlyStringIsAccepted() throws {
        let validated = try validateExtraction(
            extractionJSON(taskJSON(deadline: "2026-03-13", deadlineConfidence: 0.9))
        )

        #expect(validated.value.tasks[0].deadline?.date == iso("2026-03-13T00:00:00Z"))
    }

    @Test("date sanity is measured against the injected now, never a wall clock")
    func sanityIsRelativeToInjectedNow() throws {
        // The same payload is fine near its own date and implausible a decade earlier. If the
        // validator read the clock this test could not exist.
        let json = extractionJSON(
            taskJSON(deadline: "2036-06-01T12:00:00Z", deadlineConfidence: 0.9)
        )

        #expect(try extractionFailure(json, now: .testReference) != nil)
        #expect(try extractionFailure(json, now: iso("2036-01-01T00:00:00Z")) == nil)
    }
}

@Suite("ResponseValidator — durations must be plausible")
struct ResponseValidatorDurationTests {

    @Test("an absurd duration is rejected")
    func absurdDurationIsRejected() throws {
        let failure = try #require(
            try extractionFailure(
                extractionJSON(taskJSON(estimatedMinutes: 100_000, durationConfidence: 0.9))
            )
        )

        #expect(
            failure == .implausibleDuration(.estimatedMinutes, itemIndex: 0, minutes: 100_000)
        )
    }

    @Test("a zero-minute task is rejected")
    func zeroDurationIsRejected() throws {
        let failure = try #require(
            try extractionFailure(
                extractionJSON(taskJSON(estimatedMinutes: 0, durationConfidence: 0.9))
            )
        )

        #expect(failure == .implausibleDuration(.estimatedMinutes, itemIndex: 0, minutes: 0))
    }

    @Test("a negative duration is rejected")
    func negativeDurationIsRejected() throws {
        let failure = try #require(
            try extractionFailure(
                extractionJSON(taskJSON(estimatedMinutes: -30, durationConfidence: 0.9))
            )
        )

        #expect(failure == .implausibleDuration(.estimatedMinutes, itemIndex: 0, minutes: -30))
    }

    @Test("an ordinary estimate is accepted")
    func ordinaryDurationIsAccepted() throws {
        let validated = try validateExtraction(
            extractionJSON(taskJSON(estimatedMinutes: 30, durationConfidence: 0.9))
        )

        #expect(validated.value.tasks[0].duration?.minutes == 30)
    }

    @Test("the bounds themselves are inclusive")
    func durationBoundsAreInclusive() throws {
        let limits = ValidationLimits.default

        for minutes in [limits.minEstimatedMinutes, limits.maxEstimatedMinutes] {
            let validated = try validateExtraction(
                extractionJSON(taskJSON(estimatedMinutes: minutes, durationConfidence: 0.9))
            )
            #expect(validated.value.tasks[0].duration?.minutes == minutes)
        }
    }
}

@Suite("ResponseValidator — enums must be in range")
struct ResponseValidatorEnumTests {

    @Test("an importance NEXT does not have is rejected")
    func unknownImportanceIsRejected() throws {
        let failure = try #require(
            try extractionFailure(extractionJSON(taskJSON(importance: "URGENT!!")))
        )

        #expect(failure == .unknownEnumValue(.importance, itemIndex: 0))
    }

    @Test("every importance NEXT does have is accepted")
    func everyKnownImportanceIsAccepted() throws {
        for importance in Importance.allCases {
            let validated = try validateExtraction(
                extractionJSON(taskJSON(importance: importance.rawValue))
            )
            #expect(validated.value.tasks[0].importance == importance)
        }
    }

    @Test("a plausible-looking priority word from another product is still rejected")
    func neighbouringVocabularyIsRejected() throws {
        // "high" is what most task apps call it. NEXT has two levels on purpose
        // (PRODUCT_SPEC.md §4.8), and quietly mapping a third onto one of them would be the
        // validator making a product decision.
        let failure = try #require(
            try extractionFailure(extractionJSON(taskJSON(importance: "high")))
        )

        #expect(failure == .unknownEnumValue(.importance, itemIndex: 0))
    }
}

@Suite("ResponseValidator — confidence must be in 0...1")
struct ResponseValidatorConfidenceRangeTests {

    @Test("a confidence above one is rejected")
    func confidenceAboveOneIsRejected() throws {
        let failure = try #require(
            try extractionFailure(extractionJSON(taskJSON(titleConfidence: 1.5)))
        )

        #expect(failure == .confidenceOutOfRange(.titleConfidence, itemIndex: 0))
    }

    @Test("a negative confidence is rejected")
    func negativeConfidenceIsRejected() throws {
        let failure = try #require(
            try extractionFailure(extractionJSON(taskJSON(titleConfidence: -0.1)))
        )

        #expect(failure == .confidenceOutOfRange(.titleConfidence, itemIndex: 0))
    }

    @Test("an out-of-range deadline confidence is named as the deadline's, not the title's")
    func outOfRangeConfidenceNamesItsOwnField() throws {
        let failure = try #require(
            try extractionFailure(
                extractionJSON(
                    taskJSON(deadline: "2026-03-13T23:59:00Z", deadlineConfidence: 4)
                )
            )
        )

        #expect(failure == .confidenceOutOfRange(.deadlineConfidence, itemIndex: 0))
    }

    @Test("the endpoints zero and one are both inside the range")
    func endpointsAreValid() throws {
        for value in [0.0, 1.0] {
            let validated = try validateExtraction(
                extractionJSON(taskJSON(titleConfidence: value))
            )
            #expect(validated.value.tasks[0].titleConfidence.value == value)
        }
    }

    @Test("a confidence that is not a finite number cannot be built at all")
    func nonFiniteConfidenceIsRefused() {
        // JSON cannot carry NaN, so this guards the Swift type rather than the wire format.
        #expect(Confidence(.nan) == nil)
        #expect(Confidence(.infinity) == nil)
        #expect(Confidence(0.5) != nil)
    }

    @Test("the two poles mean what they say, and silence sits at the bottom")
    func polesAreOrdered() {
        #expect(Confidence.certain.value == 1)
        #expect(Confidence.unstated.value == 0)
        #expect(Confidence.unstated < Confidence.certain)

        // The property that makes reading silence as zero safe: it can never clear the bar to
        // act on a value unasked, whatever the threshold is later tuned to.
        #expect(Confidence.unstated.value < ValidationLimits.default.confirmationThreshold)
    }
}

@Suite("ResponseValidator — a rejection is actionable")
struct ResponseValidatorFailureShapeTests {

    @Test("a rejection says which field and which item, so recovery can be specific")
    func failuresLocateThemselves() throws {
        let failure = try #require(
            try extractionFailure(
                extractionJSON(
                    taskJSON(title: "Chemistry worksheet"),
                    taskJSON(title: "History essay", importance: "urgent")
                )
            )
        )

        #expect(failure.field == .importance)
        #expect(failure.itemIndex == 1)
    }

    @Test("a whole-response rejection blames no single field")
    func wholeResponseFailuresHaveNoField() throws {
        let failure = try #require(try extractionFailure("{ \"tasks\": [] }"))

        #expect(failure.field == nil)
        #expect(failure.itemIndex == nil)
    }
}

@Suite("ResponseValidator — uncertain is not the same as invalid")
struct ResponseValidatorUncertaintyTests {

    private let lowConfidenceDeadline = extractionJSON(
        taskJSON(
            title: "Chemistry worksheet",
            deadline: "2026-03-13T23:59:00Z",
            deadlineConfidence: 0.4
        )
    )

    @Test("a low-confidence deadline is valid data, not a failure")
    func lowConfidenceDeadlineValidates() throws {
        let validated = try validateExtraction(lowConfidenceDeadline)

        #expect(validated.value.tasks[0].deadline?.date == iso("2026-03-13T23:59:00Z"))
    }

    @Test("a low-confidence deadline is flagged for the user to confirm")
    func lowConfidenceDeadlineIsFlagged() throws {
        let validated = try validateExtraction(lowConfidenceDeadline)

        #expect(validated.requiresConfirmation)
        #expect(
            validated.confirmations == [
                FieldConfirmation(
                    itemIndex: 0,
                    field: .deadline,
                    confidence: try #require(Confidence(0.4))
                )
            ]
        )
    }

    @Test("a confident deadline is not sent to confirmation")
    func confidentDeadlineIsNotFlagged() throws {
        let validated = try validateExtraction(
            extractionJSON(
                taskJSON(deadline: "2026-03-13T23:59:00Z", deadlineConfidence: 0.97)
            )
        )

        #expect(!validated.requiresConfirmation)
    }

    @Test("an unconfirmed deadline is withheld from the task written to the database")
    func unconfirmedDeadlineIsNotWrittenThrough() throws {
        // PRODUCT_SPEC.md §4.6: ambiguous deadlines ask rather than invent certainty. A guess
        // written straight into the store *is* the invention, and it would then drive ranking,
        // notifications and the Today screen as though the user had said it.
        let validated = try validateExtraction(lowConfidenceDeadline)

        let items = validated.taskItems(
            idProvider: SequentialIDs(), createdAt: .testReference
        )

        #expect(items.count == 1)
        #expect(items[0].title == "Chemistry worksheet")
        #expect(items[0].deadline == nil)
    }

    @Test("the withheld deadline is still available for the confirmation screen to offer")
    func withheldDeadlineIsStillReadable() throws {
        // Withholding it from the database is not the same as throwing it away. Capture
        // Confirmation has to be able to show "Chemistry worksheet — Friday" and ask.
        let validated = try validateExtraction(lowConfidenceDeadline)

        #expect(validated.value.tasks[0].deadline?.date == iso("2026-03-13T23:59:00Z"))
        #expect(validated.confirmations.first?.field == .deadline)
    }

    @Test("a confident deadline is written through")
    func confidentDeadlineIsWrittenThrough() throws {
        let validated = try validateExtraction(
            extractionJSON(
                taskJSON(deadline: "2026-03-13T23:59:00Z", deadlineConfidence: 0.97)
            )
        )

        let items = validated.taskItems(
            idProvider: SequentialIDs(), createdAt: .testReference
        )

        #expect(items[0].deadline == iso("2026-03-13T23:59:00Z"))
    }

    @Test("a low-confidence duration is withheld the same way a deadline is")
    func unconfirmedDurationIsNotWrittenThrough() throws {
        let validated = try validateExtraction(
            extractionJSON(taskJSON(estimatedMinutes: 45, durationConfidence: 0.3))
        )

        let items = validated.taskItems(
            idProvider: SequentialIDs(), createdAt: .testReference
        )

        #expect(items[0].estimatedMinutes == nil)
        #expect(validated.confirmations.map(\.field) == [.estimatedMinutes])
    }

    @Test("a low title confidence is flagged but never suppresses the title")
    func lowTitleConfidenceKeepsTheTitle() throws {
        // A task with no title is not a task. The flag routes it to Capture Confirmation for
        // editing; blanking it would leave the user with a row they cannot identify.
        let validated = try validateExtraction(
            extractionJSON(taskJSON(title: "chem thing", titleConfidence: 0.2))
        )

        let items = validated.taskItems(
            idProvider: SequentialIDs(), createdAt: .testReference
        )

        #expect(items[0].title == "chem thing")
        #expect(validated.confirmations.map(\.field) == [.title])
    }

    @Test("confirmations are ordered by item and then by field, never by dictionary order")
    func confirmationsAreDeterministic() throws {
        let json = extractionJSON(
            taskJSON(title: "One", titleConfidence: 0.2),
            taskJSON(
                title: "Two",
                deadline: "2026-03-13T23:59:00Z",
                estimatedMinutes: 45,
                titleConfidence: 0.99,
                deadlineConfidence: 0.3,
                durationConfidence: 0.3
            )
        )

        let first = try validateExtraction(json)
        let second = try validateExtraction(json)

        #expect(first.confirmations == second.confirmations)
        #expect(
            first.confirmations.map { ($0.itemIndex, $0.field) }
                .map { "\($0.0):\($0.1.rawValue)" }
                == ["0:title", "1:deadline", "1:estimatedMinutes"]
        )
    }
}

@Suite("ResponseValidator — an inference is visible even when it is confident")
struct ResponseValidatorInferenceTests {

    // PRODUCT_SPEC.md §4.6 opens with "Every consequential AI inference is confirmable —
    // deadlines especially". Asking about *low* confidence is the second, narrower sentence.
    //
    // `confirmations` answers "which fields is NEXT unsure about". It cannot answer "which
    // fields did a provider make up", and those are different questions: a deadline read at 0.9
    // is written into the task with no trace, so the Capture Confirmation screen has no way to
    // distinguish it from a date the user typed by hand. `inferences` is the second answer, and
    // it is populated regardless of how sure the provider was.

    private let confidentDeadline = extractionJSON(
        taskJSON(
            title: "Chemistry worksheet",
            deadline: "2026-03-13T23:59:00Z",
            deadlineConfidence: 0.8
        )
    )

    @Test("a confident deadline is written through, and still declared an inference")
    func confidentDeadlineIsStillAnInference() throws {
        let validated = try validateExtraction(confidentDeadline)

        // Both halves matter. The first is the existing behaviour and is correct: 0.8 clears the
        // bar, so NEXT does not interrupt. The second is what lets the confirmation screen say
        // "Chemistry worksheet — Friday" rather than presenting a guess as a fact.
        #expect(!validated.requiresConfirmation)
        #expect(validated.inferredFields(ofItem: 0) == [.deadline])
        #expect(
            validated.taskItems(idProvider: SequentialIDs(), createdAt: .testReference)[0]
                .deadline == iso("2026-03-13T23:59:00Z")
        )
    }

    @Test("an uncertain deadline is both an inference and a question")
    func uncertainDeadlineIsBoth() throws {
        let validated = try validateExtraction(
            extractionJSON(
                taskJSON(deadline: "2026-03-13T23:59:00Z", deadlineConfidence: 0.4)
            )
        )

        #expect(validated.unconfirmedFields(ofItem: 0) == [.deadline])
        #expect(validated.inferredFields(ofItem: 0) == [.deadline])
    }

    @Test("a field the provider never supplied is not an inference")
    func absentFieldsAreNotInferences() throws {
        // The property that makes the set worth having: it says what a provider *did*, not what
        // the type could have carried.
        let validated = try validateExtraction(extractionJSON(taskJSON(title: "Email professor")))

        #expect(validated.inferredFields(ofItem: 0).isEmpty)
        #expect(validated.inferences.isEmpty)
    }

    @Test("a duration is an inference on the same terms as a deadline")
    func durationsAreInferencesToo() throws {
        let validated = try validateExtraction(
            extractionJSON(taskJSON(estimatedMinutes: 30, durationConfidence: 0.95))
        )

        #expect(!validated.requiresConfirmation)
        #expect(validated.inferredFields(ofItem: 0) == [.estimatedMinutes])
    }

    @Test("inferences name the item they belong to, in a fixed order")
    func inferencesAreOrderedAndLocated() throws {
        let validated = try validateExtraction(
            extractionJSON(
                taskJSON(title: "Email professor"),
                taskJSON(
                    title: "Chemistry worksheet",
                    deadline: "2026-03-13T23:59:00Z",
                    estimatedMinutes: 30,
                    deadlineConfidence: 0.9,
                    durationConfidence: 0.9
                )
            )
        )

        #expect(
            validated.inferences.map { "\($0.itemIndex):\($0.field.rawValue)" }
                == ["1:deadline", "1:estimatedMinutes"]
        )
        #expect(validated.inferredFields(ofItem: 0).isEmpty)
    }

    @Test("a standalone duration estimate is entirely an inference")
    func standaloneDurationIsAnInference() throws {
        let validated = try testValidator.validate(
            decodeDuration("{ \"estimatedMinutes\": 25, \"confidence\": 0.9 }")
        )

        #expect(!validated.requiresConfirmation)
        #expect(validated.inferredFields(ofItem: 0) == [.minutes])
    }

    @Test("a step's estimate is an inference; a step with no estimate carries none")
    func stepEstimatesAreInferences() throws {
        let validated = try testValidator.validate(
            decodeDecomposition(
                decompositionJSON(
                    stepJSON(text: "Open the assignment instructions."),
                    stepJSON(text: "Find one source.", estimatedMinutes: 10)
                )
            )
        )

        #expect(validated.inferredFields(ofItem: 0).isEmpty)
        #expect(validated.inferredFields(ofItem: 1) == [.estimatedMinutes])
    }

    @Test("the deterministic fallback declares its own readings as inferences")
    func fallbackDeadlinesAreDeclared() async throws {
        // "tomorrow" is read at 0.9 — above the bar, so it is written and nothing is asked. It
        // is still NEXT's reading of the sentence rather than a date the user chose, and the app
        // has to be able to tell.
        let validated = try await TemplateFallbackProvider().extractTasks(
            TaskExtractionRequest(
                text: "finish slides tomorrow", now: .testReference, timeZone: testTimeZone
            )
        )

        #expect(!validated.requiresConfirmation)
        #expect(validated.inferredFields(ofItem: 0) == [.deadline])
        #expect(
            validated.taskItems(idProvider: SequentialIDs(), createdAt: .testReference)[0]
                .deadline == iso("2026-03-11T23:59:00Z")
        )
    }
}

@Suite("ResponseValidator — failure is wholesale")
struct ResponseValidatorWholesaleTests {

    @Test("one bad task rejects the whole response, not just that task")
    func oneBadTaskRejectsEverything() throws {
        let json = extractionJSON(
            taskJSON(title: "Chemistry worksheet"),
            taskJSON(title: "History essay", deadline: "3000-01-01T00:00:00Z", deadlineConfidence: 0.9),
            taskJSON(title: "Email Professor Hale")
        )

        #expect(try extractionFailure(json) != nil)
    }

    @Test("the rejection names which item was at fault")
    func rejectionNamesTheItem() throws {
        let json = extractionJSON(
            taskJSON(title: "Chemistry worksheet"),
            taskJSON(title: "History essay", estimatedMinutes: 99_999, durationConfidence: 0.9),
            taskJSON(title: "Email Professor Hale")
        )

        let failure = try #require(try extractionFailure(json))

        #expect(
            failure == .implausibleDuration(.estimatedMinutes, itemIndex: 1, minutes: 99_999)
        )
    }

    @Test("validating the same payload twice gives the same answer")
    func validationIsDeterministic() throws {
        let json = extractionJSON(
            taskJSON(title: "A", deadline: "2026-03-13T23:59:00Z", deadlineConfidence: 0.4),
            taskJSON(title: "B", estimatedMinutes: 20, durationConfidence: 0.99)
        )

        let first = try validateExtraction(json)
        let second = try validateExtraction(json)

        #expect(first == second)
    }
}

@Suite("ResponseValidator — generated instruction text")
struct ResponseValidatorGeneratedTextTests {

    @Test("a decomposition validates and keeps its order")
    func decompositionValidates() throws {
        let validated = try testValidator.validate(
            decodeDecomposition(
                decompositionJSON(
                    stepJSON(text: "Open the assignment instructions."),
                    stepJSON(text: "Find one source.", estimatedMinutes: 10)
                )
            )
        )

        #expect(validated.value.steps.map(\.text) == [
            "Open the assignment instructions.", "Find one source."
        ])
        #expect(validated.value.steps[1].estimatedMinutes == 10)
    }

    @Test("a decomposition with no steps is rejected as empty")
    func emptyDecompositionIsRejected() throws {
        #expect(throws: ValidationFailure.emptyResponse(.decompose)) {
            _ = try testValidator.validate(decodeDecomposition("{ \"steps\": [] }"))
        }
    }

    @Test("more steps than the limit is rejected")
    func tooManyStepsIsRejected() throws {
        let limit = ValidationLimits.default.maxStepsPerDecomposition
        let steps = (0...limit).map { stepJSON(text: "Step \($0).") }
        let json = "{ \"steps\": [\(steps.joined(separator: ", "))] }"

        #expect(
            throws: ValidationFailure.tooManyItems(.decompose, count: limit + 1, limit: limit)
        ) {
            _ = try testValidator.validate(decodeDecomposition(json))
        }
    }

    @Test("one bad step rejects the whole decomposition")
    func oneBadStepRejectsTheDecomposition() throws {
        let json = decompositionJSON(
            stepJSON(text: "Open the assignment instructions."),
            stepJSON(text: nil),
            stepJSON(text: "Write one paragraph.")
        )

        #expect(throws: ValidationFailure.missingRequiredField(.step, itemIndex: 1)) {
            _ = try testValidator.validate(decodeDecomposition(json))
        }
    }

    @Test("a next action validates")
    func nextActionValidates() throws {
        let validated = try testValidator.validate(
            decodeNextAction("{ \"nextAction\": \"Find three sources.\", \"confidence\": 0.9 }")
        )

        #expect(validated.value.text == "Find three sources.")
    }

    @Test("a next action with no text is rejected")
    func nextActionWithoutTextIsRejected() throws {
        #expect(throws: ValidationFailure.missingRequiredField(.nextAction, itemIndex: nil)) {
            _ = try testValidator.validate(decodeNextAction("{ \"confidence\": 0.9 }"))
        }
    }

    @Test("a duration estimate validates and is bounded")
    func durationEstimateIsBounded() throws {
        let good = try testValidator.validate(
            decodeDuration("{ \"estimatedMinutes\": 25, \"confidence\": 0.8 }")
        )
        #expect(good.value.minutes == 25)

        #expect(
            throws: ValidationFailure.implausibleDuration(.minutes, itemIndex: nil, minutes: 0)
        ) {
            _ = try testValidator.validate(
                decodeDuration("{ \"estimatedMinutes\": 0, \"confidence\": 0.8 }")
            )
        }
    }

    @Test("a simplification validates")
    func simplificationValidates() throws {
        let validated = try testValidator.validate(
            decodeSimplification("{ \"step\": \"Open your notes.\", \"confidence\": 0.85 }")
        )

        #expect(validated.value.text == "Open your notes.")
    }

    @Test("an over-long step is rejected")
    func overlongStepIsRejected() throws {
        let limit = ValidationLimits.default.maxStepLength
        let long = String(repeating: "b", count: limit + 1)

        #expect(
            throws: ValidationFailure.fieldTooLong(
                .step, itemIndex: 0, length: limit + 1, limit: limit
            )
        ) {
            _ = try testValidator.validate(
                decodeDecomposition(decompositionJSON(stepJSON(text: long)))
            )
        }
    }

    @Test("a low-confidence step is valid, and flagged")
    func lowConfidenceStepIsFlagged() throws {
        let validated = try testValidator.validate(
            decodeSimplification("{ \"step\": \"Open your notes.\", \"confidence\": 0.2 }")
        )

        #expect(validated.value.text == "Open your notes.")
        #expect(validated.confirmations.map(\.field) == [.step])
    }
}

@Suite("ResponseValidator — tone is part of validity")
struct ResponseValidatorToneTests {

    @Test("a step that judges the user is rejected")
    func judgementalStepIsRejected() throws {
        // P5: never shame the user. Tone is a product invariant, and an invariant that a model
        // can talk its way past is not an invariant.
        for text in [
            "Stop being lazy and open the book.",
            "You have failed to start this three times.",
            "Do not break your streak.",
            "You should have started this last week."
        ] {
            #expect(
                throws: ValidationFailure.unacceptableTone(.step, itemIndex: 0),
                "accepted: \(text)"
            ) {
                _ = try testValidator.validate(
                    decodeDecomposition(decompositionJSON(stepJSON(text: text)))
                )
            }
        }
    }

    @Test("a step that diagnoses the user is rejected")
    func clinicalStepIsRejected() throws {
        // PRODUCT_SPEC.md §1: NEXT does not diagnose anything, ever.
        for text in [
            "Work with your ADHD, not against it.",
            "This is executive dysfunction talking.",
            "Your brain can't hold a task this big.",
            "Your brain is not wired for long sessions.",
            "Given your diagnosis, try a shorter session.",
            "Since you have been diagnosed, start smaller."
        ] {
            #expect(
                throws: ValidationFailure.unacceptableTone(.step, itemIndex: 0),
                "accepted: \(text)"
            ) {
                _ = try testValidator.validate(
                    decodeDecomposition(decompositionJSON(stepJSON(text: text)))
                )
            }
        }
    }

    @Test("coursework vocabulary is not mistaken for NEXT diagnosing the user")
    func clinicalSubjectMatterIsNotClinicalTone() throws {
        // The screen judges what NEXT is *saying about the user*, not what the user is studying.
        // NEXT's audience is undergraduates, and psychology and neuroscience students are
        // squarely in it: a step that names a diagnostic manual or a brain stem is ordinary
        // coursework. Rejecting one is not a small cost either — failure is wholesale, so a
        // single such step throws away the entire decomposition and drops the user to the
        // generic ladder for a task NEXT actually understood.
        for text in [
            "Read the diagnostic criteria section.",
            "Open the neuroscience notes on your brain stem.",
            "Summarise the diagnostic interview transcript.",
            "Label the brain diagram."
        ] {
            let validated = try testValidator.validate(
                decodeDecomposition(decompositionJSON(stepJSON(text: text)))
            )
            #expect(validated.value.steps[0].text == text, "rejected: \(text)")
        }
    }

    @Test("the user's own words are never screened for tone")
    func extractedTitlesAreNotScreened() throws {
        // A student really can have "Read the ADHD chapter" or "Essay on anxiety in Hamlet" on
        // their list. Tone screening exists to stop NEXT talking that way *to* the user; it must
        // never censor what the user said about their own work.
        for title in [
            "Read the ADHD chapter",
            "Essay on anxiety in Hamlet",
            "Revise executive dysfunction case study",
            "Therapy appointment paperwork"
        ] {
            let validated = try validateExtraction(extractionJSON(taskJSON(title: title)))
            #expect(validated.value.tasks[0].title == title)
        }
    }

    @Test("an ordinary instruction passes the screen untouched")
    func ordinaryStepsPass() throws {
        for kind in WorkKind.allCases {
            for text in kind.firstSteps {
                let validated = try testValidator.validate(
                    decodeDecomposition(decompositionJSON(stepJSON(text: text)))
                )
                #expect(validated.value.steps[0].text == text)
            }
        }
    }
}
