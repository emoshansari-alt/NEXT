import Foundation
import Testing

@testable import NextKit

// PRIVACY.md: "An AI request carries only the text required for that one operation. Breaking
// down one task sends that task — never the task list, never completion history, never anything
// about other assignments." Explicitly forbidden in any request: the full task database,
// completion history, rejection history, device identifiers, or any stable user identifier.
//
// The data NEXT handles is unusually sensitive for a productivity app — task titles say what a
// student is studying, what they are behind on, and what they are avoiding — so these are tests
// rather than comments.

/// A task carrying every kind of context that must not travel. The distinctive marker makes an
/// accidental leak visible wherever it surfaces.
private func loadedTask() -> TaskItem {
    makeTask(
        id: "must-not-travel-id",
        title: "History essay",
        status: .active,
        deadline: .daysFromReference(3),
        importance: .important,
        estimatedMinutes: 90,
        nextAction: "must-not-travel-next-action",
        prerequisiteIDs: [TaskID("must-not-travel-prerequisite")],
        parentID: TaskID("must-not-travel-parent"),
        rejections: [rejection(.needLessEffort, hoursAgo: 2)]
    )
}

private func encoded(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

@Suite("Intelligence — requests carry the minimum")
struct IntelligenceRequestPrivacyTests {

    @Test("a request built from a task carries the work, and nothing about the user")
    func requestsDropEverythingButTheWork() throws {
        let task = loadedTask()

        let requests: [String] = [
            try encoded(DecompositionRequest(task: task)),
            try encoded(NextActionRequest(task: task)),
            try encoded(DurationEstimateRequest(task: task)),
            try encoded(SimplificationRequest(task: task, path: .tooMuch))
        ]

        for request in requests {
            #expect(!request.contains("must-not-travel"), "leaked: \(request)")
        }
    }

    @Test("the rejection history never leaves, especially not to Rescue")
    func rejectionHistoryNeverTravels() throws {
        // The one a well-meaning optimisation would add, because it looks useful. A record of
        // what someone has been avoiding, sent to a provider, on the day they asked for help,
        // is exactly the transfer PRIVACY.md rules out.
        let request = try encoded(SimplificationRequest(task: loadedTask(), path: .dontWantTo))

        #expect(!request.contains("needLessEffort"))
        #expect(!request.contains("rejection"))
    }

    @Test("no request type can hold a task identifier or a collection of anything")
    func requestsAreFlatAndAnonymous() {
        // Structural rather than incidental. Adding `tasks: [TaskItem]` — or even a `TaskID` for
        // "correlation" — to any of these types trips this test, which is the point: sending the
        // whole database should require an argument, not an afternoon.
        let allowed: Set<String> = ["String", "Optional<Int>", "Int", "Date", "TimeZone", "RescuePath"]

        let requests: [Any] = [
            TaskExtractionRequest(text: "chem test monday", now: .testReference, timeZone: testTimeZone),
            DecompositionRequest(task: loadedTask()),
            NextActionRequest(task: loadedTask()),
            DurationEstimateRequest(task: loadedTask()),
            SimplificationRequest(task: loadedTask(), path: .tooMuch)
        ]

        for request in requests {
            for child in Mirror(reflecting: request).children {
                let name = String(describing: type(of: child.value))
                #expect(
                    allowed.contains(name),
                    "\(type(of: request)).\(child.label ?? "?") is a \(name)"
                )
            }
        }
    }

    @Test("extraction sends the text the user typed and no surrounding state")
    func extractionSendsOnlyTheText() throws {
        let request = try encoded(
            TaskExtractionRequest(
                text: "chem test monday", now: .testReference, timeZone: testTimeZone
            )
        )

        #expect(request.contains("chem test monday"))
        #expect(!request.contains("must-not-travel"))
    }
}

@Suite("Intelligence — failures carry no task text")
struct IntelligenceErrorPrivacyTests {

    @Test("a validation failure names the field, never the value")
    func validationFailuresNameFieldsOnly() throws {
        // PRIVACY.md: task text must never reach a log line, breadcrumb, crash report or error
        // message. A validation failure is the single likeliest thing to be logged, and a
        // malformed model response very often contains a mangled echo of the prompt.
        let marker = "MUSTNOTAPPEARINALOG"
        let json = extractionJSON(
            taskJSON(title: marker, deadline: "3000-01-01T00:00:00Z", deadlineConfidence: 0.9)
        )

        let failure = try #require(try extractionFailure(json))

        #expect(!String(describing: failure).contains(marker))
    }

    @Test("no failure case can carry free text at all")
    func noFailureCaseHoldsAString() {
        // Every payload across every case, reflected. A future case with a `String` payload —
        // "helpfully" including the offending value — fails here rather than in production.
        let failures: [ValidationFailure] = [
            .emptyResponse(.extractTasks),
            .tooManyItems(.extractTasks, count: 51, limit: 50),
            .missingRequiredField(.title, itemIndex: 0),
            .fieldTooLong(.title, itemIndex: 0, length: 401, limit: 400),
            .unparseableDate(.deadline, itemIndex: 0),
            .implausibleDate(.deadline, itemIndex: 0),
            .implausibleDuration(.estimatedMinutes, itemIndex: 0, minutes: 100_000),
            .unknownEnumValue(.importance, itemIndex: 0),
            .confidenceOutOfRange(.titleConfidence, itemIndex: 0),
            .unacceptableTone(.step, itemIndex: 0)
        ]

        for failure in failures {
            for child in Mirror(reflecting: failure).children {
                for payload in Mirror(reflecting: child.value).children {
                    #expect(
                        !(payload.value is String),
                        "\(failure) carries a String payload"
                    )
                }
            }
        }
    }

    @Test("a provider failure never echoes the text it choked on")
    func providerFailuresDoNotEcho() async throws {
        let marker = "MUSTNOTAPPEARINALOG"
        let provider = MockIntelligenceProvider(
            .payload("{ \"tasks\": [ { \"title\": \"\(marker)")
        )

        do {
            _ = try await provider.extractTasks(
                TaskExtractionRequest(text: marker, now: .testReference, timeZone: testTimeZone)
            )
            Issue.record("malformed payload was accepted")
        } catch {
            #expect(!String(describing: error).contains(marker))
        }
    }

    @Test("the fallback's own refusals carry no text either")
    func fallbackRefusalsCarryNoText() async throws {
        let marker = String(repeating: "Z", count: ValidationLimits.default.maxTitleLength + 1)

        do {
            _ = try await TemplateFallbackProvider().extractTasks(
                TaskExtractionRequest(text: marker, now: .testReference, timeZone: testTimeZone)
            )
            Issue.record("an over-long title was accepted")
        } catch {
            #expect(!String(describing: error).contains(marker))
        }
    }
}

@Suite("Intelligence — NEXT holds itself to the gate")
struct IntelligenceSelfConsistencyTests {

    @Test("every step the deterministic layer can produce passes NEXT's own tone screen")
    func ownCopyPassesTheToneScreen() throws {
        // The screen exists to stop a model putting words in NEXT's mouth. If NEXT's own
        // shipping copy could not get through it, the screen would be calibrated against
        // nothing.
        var texts = WorkKind.allCases.flatMap(\.firstSteps)
        texts += StepShrinker.genericSteps.map(\.text)

        for text in texts {
            let validated = try testValidator.validate(
                decodeDecomposition(decompositionJSON(stepJSON(text: text)))
            )
            #expect(validated.value.steps[0].text == text)
        }
    }

    @Test("every step is inside the length bound the validator enforces")
    func ownCopyIsWithinBounds() {
        let limit = ValidationLimits.default.maxStepLength

        for text in WorkKind.allCases.flatMap(\.firstSteps) {
            #expect(text.count <= limit, "\(text.count) characters: \(text)")
        }
    }
}
