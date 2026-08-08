import Foundation
import Testing

@testable import NextKit

// Helpers shared by the Intelligence test files.
//
// Deliberately a *new* file rather than an addition to `Support/TestSupport.swift`: the shared
// support file is the property of the whole suite, and these helpers exist only to make
// untrusted-payload tests readable.
//
// Everything here builds raw JSON text on purpose. The point of this module is that a provider
// hands NEXT bytes it did not author, so the tests must start from bytes too — building a
// `TaskExtractionResponse` in Swift would quietly prove the wrong thing.

/// UTC, stated explicitly. `NextKit` no more reads the ambient time zone than it reads the
/// clock, so every date-sensitive test names the zone it means (DECISIONS.md D-007).
let testTimeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "UTC")!

/// The shipping validator, with the shipping limits.
let testValidator = ResponseValidator()

/// Mints readable, ordered identifiers, so that capture results can be asserted exactly.
///
/// `NextKit` ships no concrete `IDProvider` — a real one has to call `UUID()`, which D-007
/// bans. Tests supply their own, which is precisely how the seam is meant to be used.
final class SequentialIDs: IDProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var issued = 0

    func makeTaskID() -> TaskID {
        lock.lock()
        defer { lock.unlock() }
        issued += 1
        return TaskID("captured-\(issued)")
    }
}

// MARK: - Decoding

func decodeExtraction(_ json: String) throws -> TaskExtractionResponse {
    try ResponseValidator.decode(
        TaskExtractionResponse.self, from: Data(json.utf8), operation: .extractTasks
    )
}

func decodeDecomposition(_ json: String) throws -> DecompositionResponse {
    try ResponseValidator.decode(
        DecompositionResponse.self, from: Data(json.utf8), operation: .decompose
    )
}

func decodeNextAction(_ json: String) throws -> NextActionResponse {
    try ResponseValidator.decode(
        NextActionResponse.self, from: Data(json.utf8), operation: .nextAction
    )
}

func decodeDuration(_ json: String) throws -> DurationEstimateResponse {
    try ResponseValidator.decode(
        DurationEstimateResponse.self, from: Data(json.utf8), operation: .estimateDuration
    )
}

func decodeSimplification(_ json: String) throws -> SimplificationResponse {
    try ResponseValidator.decode(
        SimplificationResponse.self, from: Data(json.utf8), operation: .simplify
    )
}

// MARK: - Validating

/// Runs a raw extraction payload through the whole gate, as a provider would.
func validateExtraction(
    _ json: String, now: Date = .testReference
) throws -> Validated<TaskExtraction> {
    try testValidator.validate(decodeExtraction(json), now: now)
}

/// The rejection a payload produces, or `nil` if the gate let it through.
func extractionFailure(_ json: String, now: Date = .testReference) throws -> ValidationFailure? {
    do {
        _ = try testValidator.validate(decodeExtraction(json), now: now)
        return nil
    } catch let failure as ValidationFailure {
        return failure
    }
}

// MARK: - Payload building

/// One task object, as a model would emit it. Pass `nil` to omit a key entirely — an absent
/// key and a null are different kinds of wrong and the validator has to survive both.
func taskJSON(
    title: String? = "Chemistry worksheet",
    deadline: String? = nil,
    estimatedMinutes: Int? = nil,
    importance: String? = nil,
    titleConfidence: Double? = 0.95,
    deadlineConfidence: Double? = nil,
    durationConfidence: Double? = nil
) -> String {
    var fields: [String] = []
    if let title { fields.append("\"title\": \(quoted(title))") }
    if let deadline { fields.append("\"deadline\": \(quoted(deadline))") }
    if let estimatedMinutes { fields.append("\"estimatedMinutes\": \(estimatedMinutes)") }
    if let importance { fields.append("\"importance\": \(quoted(importance))") }

    var confidence: [String] = []
    if let titleConfidence { confidence.append("\"title\": \(number(titleConfidence))") }
    if let deadlineConfidence { confidence.append("\"deadline\": \(number(deadlineConfidence))") }
    if let durationConfidence { confidence.append("\"duration\": \(number(durationConfidence))") }
    if !confidence.isEmpty {
        fields.append("\"confidence\": { \(confidence.joined(separator: ", ")) }")
    }

    return "{ \(fields.joined(separator: ", ")) }"
}

/// A whole extraction payload wrapping the given task objects.
func extractionJSON(_ tasks: String...) -> String {
    "{ \"tasks\": [\(tasks.joined(separator: ", "))] }"
}

/// One decomposition step object.
func stepJSON(
    text: String? = "Open the assignment instructions.",
    estimatedMinutes: Int? = nil,
    confidence: Double? = 0.9
) -> String {
    var fields: [String] = []
    if let text { fields.append("\"text\": \(quoted(text))") }
    if let estimatedMinutes { fields.append("\"estimatedMinutes\": \(estimatedMinutes)") }
    if let confidence { fields.append("\"confidence\": \(number(confidence))") }
    return "{ \(fields.joined(separator: ", ")) }"
}

func decompositionJSON(_ steps: String...) -> String {
    "{ \"steps\": [\(steps.joined(separator: ", "))] }"
}

private func quoted(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
    return "\"\(escaped)\""
}

/// JSON has no notion of a Swift `Double` description, so numbers are written plainly.
/// `Double.nan` deliberately renders as the bare token `NaN`, which is *not* legal JSON —
/// tests that need a non-finite confidence build the payload differently.
private func number(_ value: Double) -> String {
    value == value.rounded() && value.isFinite ? String(Int(value)) : String(value)
}
