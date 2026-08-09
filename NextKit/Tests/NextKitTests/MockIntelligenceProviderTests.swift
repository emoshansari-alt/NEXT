import Foundation
import Testing

@testable import NextKit

// The mock exists so that the eight ways a provider goes wrong can be exercised on purpose,
// rather than discovered in the wild. Each failure mode gets its own test, and each test asserts
// two things: nothing crashes, and nothing corrupt survives.
//
// A note on the timeout mode: it throws, it does not wait. `NextKit` may not call `Task.sleep`
// (ARCHITECTURE.md §3), and a test suite that spends real seconds proving a timer works is a
// test suite people stop running.

private func extractionRequest(
    _ text: String = "chem test monday", now: Date = .testReference
) -> TaskExtractionRequest {
    TaskExtractionRequest(text: text, now: now, timeZone: testTimeZone)
}

/// Calls one operation on a provider with a plausible request, discarding the answer.
/// Used by the matrix tests, which care only whether a call throws.
private func call(
    _ operation: IntelligenceOperation,
    on provider: any IntelligenceProvider
) async throws {
    switch operation {
    case .extractTasks:
        _ = try await provider.extractTasks(extractionRequest())
    case .decompose:
        _ = try await provider.decompose(
            DecompositionRequest(title: "History essay", estimatedMinutes: 90, maxSteps: 6)
        )
    case .nextAction:
        _ = try await provider.nextAction(NextActionRequest(title: "History essay"))
    case .estimateDuration:
        _ = try await provider.estimateDuration(
            DurationEstimateRequest(title: "History essay")
        )
    case .simplify:
        _ = try await provider.simplify(
            SimplificationRequest(title: "History essay", path: .tooMuch)
        )
    }
}

@Suite("MockIntelligenceProvider — the eight failure modes")
struct MockFailureModeTests {

    private func mock(_ mode: IntelligenceFailureMode) -> MockIntelligenceProvider {
        MockIntelligenceProvider(.failureMode(mode))
    }

    @Test("1. a timeout surfaces as a timeout, not as an empty result")
    func timeout() async throws {
        await #expect(throws: IntelligenceError.timedOut(.extractTasks)) {
            _ = try await mock(.timeout).extractTasks(extractionRequest())
        }
    }

    @Test("2. malformed JSON is refused before anything is interpreted")
    func malformedJSON() async throws {
        await #expect(throws: IntelligenceError.malformedResponse(.extractTasks)) {
            _ = try await mock(.malformedJSON).extractTasks(extractionRequest())
        }
    }

    @Test("3. a well-formed response containing nothing is refused")
    func emptyResponse() async throws {
        await #expect(
            throws: IntelligenceError.validationFailed(.emptyResponse(.extractTasks))
        ) {
            _ = try await mock(.emptyResponse).extractTasks(extractionRequest())
        }
    }

    @Test("4. an impossible date is refused rather than stored")
    func impossibleDate() async throws {
        // Left unchecked this is the worst of the eight: a task dated in the year 3000 is never
        // urgent, so it would sink to the bottom of the ranking and quietly never be shown.
        await #expect(
            throws: IntelligenceError.validationFailed(
                .implausibleDate(.deadline, itemIndex: 0)
            )
        ) {
            _ = try await mock(.impossibleDate).extractTasks(extractionRequest())
        }
    }

    @Test("5. an unreasonable duration is refused")
    func unreasonableDuration() async throws {
        await #expect(
            throws: IntelligenceError.validationFailed(
                .implausibleDuration(.estimatedMinutes, itemIndex: 0, minutes: 100_000)
            )
        ) {
            _ = try await mock(.unreasonableDuration).extractTasks(extractionRequest())
        }
    }

    @Test("6. a missing required field is refused")
    func missingRequiredField() async throws {
        await #expect(
            throws: IntelligenceError.validationFailed(
                .missingRequiredField(.title, itemIndex: 0)
            )
        ) {
            _ = try await mock(.missingRequiredField).extractTasks(extractionRequest())
        }
    }

    @Test("7. an enum value NEXT does not have is refused")
    func invalidEnum() async throws {
        await #expect(
            throws: IntelligenceError.validationFailed(
                .unknownEnumValue(.importance, itemIndex: 0)
            )
        ) {
            _ = try await mock(.invalidEnum).extractTasks(extractionRequest())
        }
    }

    @Test("8. a partial response is refused whole, not applied in part")
    func partialResponse() async throws {
        // Two of the three tasks in this payload are perfectly good. None of them lands.
        await #expect(
            throws: IntelligenceError.validationFailed(
                .implausibleDate(.deadline, itemIndex: 1)
            )
        ) {
            _ = try await mock(.partialResponse).extractTasks(extractionRequest())
        }
    }

    @Test("there are exactly eight, and they are these eight, in this order")
    func eightModesExist() {
        // Written out rather than counted. A `Set(…).count == 8` on a `String` enum with eight
        // distinctly named cases is guaranteed by the compiler and cannot report anything: it
        // would still pass if a mode were renamed, reordered, or swapped for a different one.
        // The names are the contract — `IntelligenceFailureMode` is `Codable`, and the order is
        // documented as "roughly how early it fails" — so both are stated.
        #expect(
            IntelligenceFailureMode.allCases.map(\.rawValue) == [
                "timeout",
                "malformedJSON",
                "emptyResponse",
                "impossibleDate",
                "unreasonableDuration",
                "missingRequiredField",
                "invalidEnum",
                "partialResponse"
            ]
        )
    }
}

@Suite("MockIntelligenceProvider — no failure yields data")
struct MockFailureContainmentTests {

    @Test("every failure mode on every operation throws, and returns nothing")
    func everyModeOnEveryOperationThrows() async throws {
        // Forty combinations, and only twenty-six of them are injections. For a mode that does
        // not apply to an operation the mock refuses before producing any bytes at all, so
        // "it threw" is true for a reason that has nothing to do with the failure being
        // injected. Counting those as covered is how a matrix test flatters itself.
        //
        // So the applicable pairings additionally assert the error is *not* the refusal: the day
        // a mode stops generating its bad payload, this fails instead of quietly shrinking to
        // fourteen real cases.
        var injected = 0

        for mode in IntelligenceFailureMode.allCases {
            for operation in IntelligenceOperation.allCases {
                let provider = MockIntelligenceProvider(.failureMode(mode))
                let applicable = mode.applicableOperations.contains(operation)
                if applicable { injected += 1 }

                var threw = false
                var refused = false
                do {
                    try await call(operation, on: provider)
                } catch let error as IntelligenceError {
                    threw = true
                    refused = error == .providerFailure(
                        operation: operation,
                        code: MockIntelligenceProvider.inapplicableModeCode
                    )
                } catch {
                    threw = true
                }

                #expect(threw, "\(mode) on \(operation) returned a value")
                if applicable {
                    #expect(!refused, "\(mode) on \(operation) refused instead of failing")
                }
            }
        }

        #expect(injected == 26)
    }

    @Test("no failure mode can put anything in the task database")
    func noFailureModeWritesToTheDatabase() async throws {
        // The sentence this whole module exists to make true: "No AI response should be capable
        // of corrupting the local task database" (PRODUCT_SPEC.md §6). Asserted end to end,
        // through the repository, rather than inferred from the validator's return type.
        for mode in IntelligenceFailureMode.allCases {
            let provider = MockIntelligenceProvider(.failureMode(mode))
            let repository = InMemoryTaskRepository()

            do {
                let validated = try await provider.extractTasks(extractionRequest())
                for item in validated.taskItems(
                    idProvider: SequentialIDs(), createdAt: .testReference
                ) {
                    try await repository.upsert(item)
                }
            } catch {
                // Expected. The point is what is in the store afterwards.
            }

            let stored = try await repository.fetchAll()
            #expect(stored.isEmpty, "\(mode) wrote \(stored.count) task(s)")
        }
    }

    @Test("a transport failure is reported as itself")
    func transportFailuresPassThrough() async throws {
        let provider = MockIntelligenceProvider(
            .transportFailure(.unavailable(.consentNotGiven))
        )

        await #expect(throws: IntelligenceError.unavailable(.consentNotGiven)) {
            _ = try await provider.extractTasks(extractionRequest())
        }
    }
}

@Suite("MockIntelligenceProvider — scripting")
struct MockScriptingTests {

    @Test("a scripted payload comes back validated")
    func scriptedPayloadValidates() async throws {
        let provider = MockIntelligenceProvider(
            .payload(extractionJSON(taskJSON(title: "Chemistry worksheet")))
        )

        let validated = try await provider.extractTasks(extractionRequest())

        #expect(validated.value.tasks.map(\.title) == ["Chemistry worksheet"])
    }

    @Test("a scripted payload still has to pass the gate")
    func scriptedPayloadIsStillValidated() async throws {
        // The mock is not a way around the validator. It is a way to reach it with chosen bytes.
        let provider = MockIntelligenceProvider(
            .payload(extractionJSON(taskJSON(titleConfidence: 12)))
        )

        await #expect(
            throws: IntelligenceError.validationFailed(
                .confidenceOutOfRange(.titleConfidence, itemIndex: 0)
            )
        ) {
            _ = try await provider.extractTasks(extractionRequest())
        }
    }

    @Test("operations can be scripted one at a time")
    func perOperationScripting() async throws {
        let provider = MockIntelligenceProvider(
            scripts: [
                .extractTasks: .payload(extractionJSON(taskJSON(title: "Chemistry worksheet"))),
                .nextAction: .failureMode(.timeout)
            ]
        )

        let extracted = try await provider.extractTasks(extractionRequest())
        #expect(extracted.value.tasks.count == 1)

        await #expect(throws: IntelligenceError.timedOut(.nextAction)) {
            _ = try await provider.nextAction(NextActionRequest(title: "History essay"))
        }
    }

    @Test("a script can be changed after the provider is built")
    func scriptsCanBeReplaced() async throws {
        let provider = MockIntelligenceProvider(.failureMode(.timeout))

        await provider.script(
            .payload(extractionJSON(taskJSON(title: "Chemistry worksheet"))),
            for: .extractTasks
        )

        let validated = try await provider.extractTasks(extractionRequest())
        #expect(validated.value.tasks.count == 1)
    }

    @Test("an unscripted operation refuses rather than inventing an answer")
    func unscriptedOperationRefuses() async throws {
        let provider = MockIntelligenceProvider()

        await #expect(
            throws: IntelligenceError.providerFailure(
                operation: .decompose, code: MockIntelligenceProvider.unscriptedCode
            )
        ) {
            _ = try await provider.decompose(
                DecompositionRequest(title: "History essay", estimatedMinutes: nil, maxSteps: 4)
            )
        }
    }

    @Test("the mock records what it was asked, in order")
    func callsAreRecorded() async throws {
        let provider = MockIntelligenceProvider(.failureMode(.timeout))

        for operation in IntelligenceOperation.allCases {
            try? await call(operation, on: provider)
        }

        let calls = await provider.calls
        #expect(calls == IntelligenceOperation.allCases)
    }

    @Test("the working default answers every operation it claims to support")
    func workingDefaultAnswersEverything() async throws {
        let provider = MockIntelligenceProvider(scripts: MockIntelligenceProvider.workingScripts)

        for operation in IntelligenceOperation.allCases {
            try await call(operation, on: provider)
        }
    }

    @Test("the mock claims every operation, including the one the fallback declines")
    func supportsEverything() async throws {
        // Named one at a time rather than compared against `Set(IntelligenceOperation.allCases)`,
        // which is the expression the property is implemented with — a comparison of an
        // expression to itself agrees no matter what either side means.
        let mock = MockIntelligenceProvider(scripts: MockIntelligenceProvider.workingScripts)

        #expect(mock.supports(.extractTasks))
        #expect(mock.supports(.decompose))
        #expect(mock.supports(.nextAction))
        #expect(mock.supports(.simplify))
        #expect(mock.supportedOperations.count == 5)

        // `estimateDuration` is the one `TemplateFallbackProvider` refuses, so the mock is the
        // only seam that can drive the app's duration path at all. A claim it could not honour
        // would be worse than no claim, so the claim is checked against an actual answer.
        #expect(mock.supports(.estimateDuration))
        let estimate = try await mock.estimateDuration(
            DurationEstimateRequest(title: "History essay")
        )
        #expect(estimate.value.minutes == 30)
    }
}
