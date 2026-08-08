import Foundation

/// A provider that returns whatever it was told to, including nonsense.
///
/// The intelligence seam's test double (ARCHITECTURE.md §3). Its job is not to be a plausible
/// model — it is to make every failure in `IntelligenceFailureMode` reproducible on demand, so
/// that the app's recovery paths are exercised deliberately instead of being discovered by a
/// user on a train.
///
/// ## It does not bypass the validator
///
/// A scripted payload is decoded and validated exactly as a real provider's bytes would be.
/// That is the point: the mock is not a shortcut past the gate, it is a way of driving chosen
/// bytes *into* it. It could not cheat even if it wanted to — `Validated` has no initialiser
/// reachable from this file.
///
/// ## It never sleeps
///
/// `timeout` throws immediately. `NextKit` may not call `Task.sleep` (ARCHITECTURE.md §3), and a
/// suite that spends real seconds proving a timer elapses is a suite people stop running. What
/// matters for the code under test is the error, not the wait.
///
/// It is an `actor` because scripts and the call log are mutable state reached from wherever the
/// caller happens to be, for the same reason `InMemoryTaskRepository` is one.
public actor MockIntelligenceProvider: IntelligenceProvider {

    /// What the mock should do when an operation is called.
    public enum Script: Hashable, Sendable {

        /// Return these bytes, then decode and validate them for real.
        case payload(String)

        /// Fail before any bytes exist — no network, no consent, cancelled, timed out.
        case transportFailure(IntelligenceError)

        /// Produce one of the eight known failure modes.
        case failureMode(IntelligenceFailureMode)
    }

    /// The code reported when an operation was never scripted.
    ///
    /// Refusing is deliberate. A mock that returned a cheerful default for anything it was not
    /// asked about would let a test pass while exercising nothing.
    public static let unscriptedCode = "mock.unscripted"

    /// The code reported when a failure mode has no meaning for the operation requested.
    public static let inapplicableModeCode = "mock.mode-not-applicable"

    private var scripts: [IntelligenceOperation: Script]
    private var recorded: [IntelligenceOperation] = []
    private let validator: ResponseValidator

    public init(
        scripts: [IntelligenceOperation: Script] = [:],
        validator: ResponseValidator = ResponseValidator()
    ) {
        self.scripts = scripts
        self.validator = validator
    }

    /// One script for every operation.
    public init(_ script: Script, validator: ResponseValidator = ResponseValidator()) {
        self.init(
            scripts: Dictionary(
                uniqueKeysWithValues: IntelligenceOperation.allCases.map { ($0, script) }
            ),
            validator: validator
        )
    }

    /// The mock answers everything, because a test seam that could not reach an operation would
    /// leave that operation untested.
    public nonisolated var supportedOperations: Set<IntelligenceOperation> {
        Set(IntelligenceOperation.allCases)
    }

    // MARK: - Scripting

    public func script(_ script: Script, for operation: IntelligenceOperation) {
        scripts[operation] = script
    }

    /// Every operation asked of this provider, in order. The check for "did the app fall back
    /// without asking" and "did it ask twice".
    public var calls: [IntelligenceOperation] { recorded }

    /// A set of scripts under which every operation succeeds.
    ///
    /// For tests whose subject is something else entirely and which merely need a provider that
    /// works. Deliberately a value rather than a preconfigured instance, so that a caller who
    /// wants one operation to misbehave can start here and replace it.
    public static var workingScripts: [IntelligenceOperation: Script] {
        [
            .extractTasks: .payload(
                """
                { "tasks": [ { "title": "Chemistry worksheet",
                               "estimatedMinutes": 30,
                               "importance": "normal",
                               "confidence": { "title": 0.95, "duration": 0.8 } } ] }
                """
            ),
            .decompose: .payload(
                """
                { "steps": [ { "text": "Open the worksheet.", "confidence": 0.9 },
                             { "text": "Read question 1.", "confidence": 0.9 } ] }
                """
            ),
            .nextAction: .payload(
                """
                { "nextAction": "Open the worksheet.", "confidence": 0.9 }
                """
            ),
            .estimateDuration: .payload(
                """
                { "estimatedMinutes": 30, "confidence": 0.7 }
                """
            ),
            .simplify: .payload(
                """
                { "step": "Read question 1.", "confidence": 0.85 }
                """
            )
        ]
    }

    // MARK: - IntelligenceProvider

    public func extractTasks(
        _ request: TaskExtractionRequest
    ) async throws -> Validated<TaskExtraction> {
        let json = try body(for: .extractTasks)
        let response = try ResponseValidator.decode(
            TaskExtractionResponse.self, from: Data(json.utf8), operation: .extractTasks
        )
        return try validator.validated(response, now: request.now)
    }

    public func decompose(
        _ request: DecompositionRequest
    ) async throws -> Validated<Decomposition> {
        let json = try body(for: .decompose)
        let response = try ResponseValidator.decode(
            DecompositionResponse.self, from: Data(json.utf8), operation: .decompose
        )
        return try validator.validated(response)
    }

    public func nextAction(
        _ request: NextActionRequest
    ) async throws -> Validated<ProposedAction> {
        let json = try body(for: .nextAction)
        let response = try ResponseValidator.decode(
            NextActionResponse.self, from: Data(json.utf8), operation: .nextAction
        )
        return try validator.validated(response)
    }

    public func estimateDuration(
        _ request: DurationEstimateRequest
    ) async throws -> Validated<DurationEstimate> {
        let json = try body(for: .estimateDuration)
        let response = try ResponseValidator.decode(
            DurationEstimateResponse.self, from: Data(json.utf8), operation: .estimateDuration
        )
        return try validator.validated(response)
    }

    public func simplify(
        _ request: SimplificationRequest
    ) async throws -> Validated<ProposedAction> {
        let json = try body(for: .simplify)
        let response = try ResponseValidator.decode(
            SimplificationResponse.self, from: Data(json.utf8), operation: .simplify
        )
        return try validator.validated(response)
    }

    // MARK: - Dispatch

    /// Records the call and produces the bytes the script asks for, or throws the way it asks.
    private func body(for operation: IntelligenceOperation) throws -> String {
        recorded.append(operation)

        guard let script = scripts[operation] else {
            throw IntelligenceError.providerFailure(
                operation: operation, code: Self.unscriptedCode
            )
        }

        switch script {
        case .payload(let json):
            return json

        case .transportFailure(let error):
            throw error

        case .failureMode(let mode):
            guard mode.applicableOperations.contains(operation) else {
                throw IntelligenceError.providerFailure(
                    operation: operation, code: Self.inapplicableModeCode
                )
            }
            if mode == .timeout { throw IntelligenceError.timedOut(operation) }
            return Self.payload(for: mode, operation: operation)
        }
    }

    // MARK: - Canned bad payloads
    //
    // Written as literal JSON rather than encoded from Swift values, because half of them
    // could not be produced by an encoder at all — that is precisely what makes them useful.

    private static func payload(
        for mode: IntelligenceFailureMode,
        operation: IntelligenceOperation
    ) -> String {
        switch operation {
        case .extractTasks: extractionPayload(for: mode)
        case .decompose: decompositionPayload(for: mode)
        case .nextAction: nextActionPayload(for: mode)
        case .estimateDuration: durationPayload(for: mode)
        case .simplify: simplificationPayload(for: mode)
        }
    }

    private static func extractionPayload(for mode: IntelligenceFailureMode) -> String {
        switch mode {
        case .timeout:
            // Unreachable: handled before the payload is asked for. Returning valid bytes here
            // would be a lie, so it returns the empty response, which fails.
            #"{ "tasks": [] }"#

        case .malformedJSON:
            #"{ "tasks": [ { "title": "Chemistry works"#

        case .emptyResponse:
            #"{ "tasks": [] }"#

        case .impossibleDate:
            """
            { "tasks": [ { "title": "Chemistry worksheet",
                           "deadline": "3000-01-01T00:00:00Z",
                           "confidence": { "title": 0.9, "deadline": 0.9 } } ] }
            """

        case .unreasonableDuration:
            """
            { "tasks": [ { "title": "Chemistry worksheet",
                           "estimatedMinutes": 100000,
                           "confidence": { "title": 0.9, "duration": 0.9 } } ] }
            """

        case .missingRequiredField:
            #"{ "tasks": [ { "estimatedMinutes": 30, "confidence": { "title": 0.9 } } ] }"#

        case .invalidEnum:
            """
            { "tasks": [ { "title": "Chemistry worksheet",
                           "importance": "urgent",
                           "confidence": { "title": 0.9 } } ] }
            """

        case .partialResponse:
            // Two good tasks and one poisoned one. Nothing survives.
            """
            { "tasks": [
                { "title": "Chemistry worksheet", "confidence": { "title": 0.95 } },
                { "title": "History essay",
                  "deadline": "3000-06-01T09:00:00Z",
                  "confidence": { "title": 0.95, "deadline": 0.9 } },
                { "title": "Email Professor Hale", "confidence": { "title": 0.95 } }
            ] }
            """
        }
    }

    private static func decompositionPayload(for mode: IntelligenceFailureMode) -> String {
        switch mode {
        case .malformedJSON:
            #"{ "steps": [ { "text": "Open the"#

        case .emptyResponse:
            #"{ "steps": [] }"#

        case .unreasonableDuration:
            """
            { "steps": [ { "text": "Open the worksheet.",
                           "estimatedMinutes": 100000,
                           "confidence": 0.9 } ] }
            """

        case .missingRequiredField:
            #"{ "steps": [ { "confidence": 0.9 } ] }"#

        case .partialResponse:
            """
            { "steps": [ { "text": "Open the worksheet.", "confidence": 0.9 },
                         { "confidence": 0.9 },
                         { "text": "Answer question 1.", "confidence": 0.9 } ] }
            """

        case .timeout, .impossibleDate, .invalidEnum:
            // Unreachable: not in `applicableOperations` for this operation.
            #"{ "steps": [] }"#
        }
    }

    private static func nextActionPayload(for mode: IntelligenceFailureMode) -> String {
        switch mode {
        case .malformedJSON:
            #"{ "nextAction": "Open the"#

        case .unreasonableDuration:
            #"{ "nextAction": "Open the worksheet.", "estimatedMinutes": 100000, "confidence": 0.9 }"#

        case .missingRequiredField:
            #"{ "confidence": 0.9 }"#

        case .timeout, .emptyResponse, .impossibleDate, .invalidEnum, .partialResponse:
            // Unreachable: not in `applicableOperations` for this operation.
            #"{ }"#
        }
    }

    private static func durationPayload(for mode: IntelligenceFailureMode) -> String {
        switch mode {
        case .malformedJSON:
            #"{ "estimatedMinutes": "#

        case .unreasonableDuration:
            #"{ "estimatedMinutes": 100000, "confidence": 0.9 }"#

        case .missingRequiredField:
            #"{ "confidence": 0.9 }"#

        case .timeout, .emptyResponse, .impossibleDate, .invalidEnum, .partialResponse:
            // Unreachable: not in `applicableOperations` for this operation.
            #"{ }"#
        }
    }

    private static func simplificationPayload(for mode: IntelligenceFailureMode) -> String {
        switch mode {
        case .malformedJSON:
            #"{ "step": "Read question"#

        case .unreasonableDuration:
            #"{ "step": "Read question 1.", "estimatedMinutes": 100000, "confidence": 0.9 }"#

        case .missingRequiredField:
            #"{ "confidence": 0.9 }"#

        case .timeout, .emptyResponse, .impossibleDate, .invalidEnum, .partialResponse:
            // Unreachable: not in `applicableOperations` for this operation.
            #"{ }"#
        }
    }
}
