import Foundation
import Testing

@testable import NextApp
import NextKit

// Capture is where untrusted extraction meets the user's data, so these tests are mostly about
// what does NOT happen: nothing written before confirmation, no uncertain deadline stored, no
// text lost when something fails.

private struct FixedTimeSource: TimeSource {
    let now: Date
}

/// Hands out predictable identifiers so assertions can name them.
private final class SequentialIDProvider: IDProvider, @unchecked Sendable {
    private var next = 0
    private let lock = NSLock()

    func makeTaskID() -> TaskID {
        lock.lock()
        defer { lock.unlock() }
        next += 1
        return TaskID("id-\(next)")
    }
}

@MainActor
@Suite("CaptureViewModel — manual entry")
struct CaptureManualEntryTests {

    private let now = Date(timeIntervalSince1970: 1_773_133_200)  // 2026-03-10 09:00 UTC

    private func model(_ repository: InMemoryTaskRepository) -> CaptureViewModel {
        CaptureViewModel(
            repository: repository,
            idProvider: SequentialIDProvider(),
            timeSource: FixedTimeSource(now: now)
        )
    }

    @Test("saves exactly what the user typed, with nothing interpreted")
    func savesVerbatim() async throws {
        // The no-model path. It must not extract a deadline, split the text, or touch anything
        // clever — this is what has to keep working when everything else is unavailable.
        let repository = InMemoryTaskRepository()
        let capture = model(repository)
        capture.text = "  chem test monday  "

        await capture.saveAsSingleTask()

        let stored = try await repository.fetchAll()
        #expect(stored.count == 1)
        #expect(stored.first?.title == "chem test monday")
        #expect(stored.first?.deadline == nil)
        #expect(stored.first?.createdAt == now)
    }

    @Test("blank text saves nothing")
    func blankSavesNothing() async throws {
        let repository = InMemoryTaskRepository()
        let capture = model(repository)
        capture.text = "   \n  "

        await capture.saveAsSingleTask()

        #expect(try await repository.fetchAll().isEmpty)
        #expect(capture.canSubmit == false)
    }

    @Test("a failed save keeps the text so nothing the user wrote is lost")
    func failedSaveKeepsText() async {
        let capture = CaptureViewModel(
            repository: FailingRepository(),
            idProvider: SequentialIDProvider(),
            timeSource: FixedTimeSource(now: now)
        )
        capture.text = "email professor"

        await capture.saveAsSingleTask()

        #expect(capture.failure != nil)
        #expect(capture.text == "email professor")
    }
}

@MainActor
@Suite("CaptureViewModel — brain dump and confirmation")
struct CaptureConfirmationTests {

    private let now = Date(timeIntervalSince1970: 1_773_133_200)

    private func model(_ repository: InMemoryTaskRepository) -> CaptureViewModel {
        CaptureViewModel(
            repository: repository,
            intelligence: TemplateFallbackProvider(),
            idProvider: SequentialIDProvider(),
            timeSource: FixedTimeSource(now: now)
        )
    }

    @Test("extraction writes nothing until the user confirms")
    func extractionDoesNotWrite() async throws {
        // The rule the whole screen exists for. AI is advisory (P3): a proposal is not data.
        let repository = InMemoryTaskRepository()
        let capture = model(repository)
        capture.text = "chem test monday, email professor, finish history slides friday"

        await capture.extract()

        #expect(capture.stage == .confirming)
        #expect(capture.proposals.isEmpty == false)
        #expect(try await repository.fetchAll().isEmpty, "nothing may be stored before confirmation")
    }

    @Test("a dump of several things becomes several tasks")
    func dumpSplitsIntoTasks() async throws {
        let repository = InMemoryTaskRepository()
        let capture = model(repository)
        capture.text = "chem test monday, email professor, finish history slides friday"

        await capture.extract()
        await capture.confirm()

        let stored = try await repository.fetchAll()
        #expect(stored.count == capture_expectedCount(3))
        #expect(stored.allSatisfy { $0.title.isEmpty == false })
    }

    // Named so the expectation reads as a claim rather than a magic number.
    private func capture_expectedCount(_ count: Int) -> Int { count }

    @Test("unticking a proposal keeps it out of the store")
    func untickedProposalsAreNotSaved() async throws {
        let repository = InMemoryTaskRepository()
        let capture = model(repository)
        capture.text = "chem test monday, email professor"
        await capture.extract()

        let first = try #require(capture.proposals.first)
        capture.setIncluded(false, forProposal: first.id)
        await capture.confirm()

        let stored = try await repository.fetchAll()
        #expect(stored.count == capture.proposals.count - 1)
        #expect(stored.contains { $0.title == first.title } == false)
    }

    @Test("editing a title before confirming stores the edit, not the guess")
    func editedTitleIsStored() async throws {
        let repository = InMemoryTaskRepository()
        let capture = model(repository)
        capture.text = "chem thing thurs"
        await capture.extract()

        let first = try #require(capture.proposals.first)
        capture.setTitle("Chemistry problem set", forProposal: first.id)
        await capture.confirm()

        #expect(try await repository.fetchAll().first?.title == "Chemistry problem set")
    }

    @Test("setting a deadline by hand stops it being a question")
    func editingADeadlineConfirmsIt() async throws {
        let repository = InMemoryTaskRepository()
        let capture = model(repository)
        capture.text = "history essay"
        await capture.extract()

        let first = try #require(capture.proposals.first)
        let chosen = now.addingTimeInterval(48 * 3600)
        capture.setDeadline(chosen, forProposal: first.id)

        let updated = try #require(capture.proposals.first)
        #expect(updated.deadline == chosen)
        #expect(updated.deadlineNeedsConfirmation == false)

        await capture.confirm()
        #expect(try await repository.fetchAll().first?.deadline == chosen)
    }

    @Test("clearing a deadline stores no deadline at all")
    func clearedDeadlineIsNotStored() async throws {
        let repository = InMemoryTaskRepository()
        let capture = model(repository)
        capture.text = "chem test monday"
        await capture.extract()

        let first = try #require(capture.proposals.first)
        capture.setDeadline(nil, forProposal: first.id)
        await capture.confirm()

        #expect(try await repository.fetchAll().first?.deadline == nil)
    }

    @Test("going back to edit keeps the text and discards the proposals")
    func returningToWritingKeepsTheText() async {
        let capture = model(InMemoryTaskRepository())
        capture.text = "chem test monday"
        await capture.extract()

        capture.returnToWriting()

        #expect(capture.stage == .writing)
        #expect(capture.proposals.isEmpty)
        #expect(capture.text == "chem test monday")
    }

    @Test("a failed confirmation loses neither the proposals nor the text")
    func failedConfirmKeepsEverything() async {
        // The batch is atomic, so a failure means nothing was written. The user must be able to
        // retry without retyping — which is the entire reason capture writes in one go.
        let capture = CaptureViewModel(
            repository: FailingRepository(),
            intelligence: TemplateFallbackProvider(),
            idProvider: SequentialIDProvider(),
            timeSource: FixedTimeSource(now: now)
        )
        capture.text = "chem test monday, email professor"
        await capture.extract()
        let proposalCount = capture.proposals.count

        await capture.confirm()

        #expect(capture.failure != nil)
        #expect(capture.proposals.count == proposalCount)
        #expect(capture.text == "chem test monday, email professor")
        #expect(capture.stage == .confirming)
    }

    @Test("nothing a proposal offers is written when every one is unticked")
    func confirmingNothingWritesNothing() async throws {
        let repository = InMemoryTaskRepository()
        let capture = model(repository)
        capture.text = "chem test monday, email professor"
        await capture.extract()

        for proposal in capture.proposals {
            capture.setIncluded(false, forProposal: proposal.id)
        }
        await capture.confirm()

        #expect(try await repository.fetchAll().isEmpty)
    }
}

@MainActor
@Suite("CaptureViewModel — extraction failure")
struct CaptureFailureTests {

    private let now = Date(timeIntervalSince1970: 1_773_133_200)

    @Test("extraction failing leaves the user with their text and a way forward")
    func extractionFailureIsRecoverable() async {
        // Offline, or a provider that is down. The product promise is that capture still works:
        // the text is untouched and manual entry is one tap away.
        let capture = CaptureViewModel(
            repository: InMemoryTaskRepository(),
            intelligence: AlwaysFailingIntelligence(),
            idProvider: SequentialIDProvider(),
            timeSource: FixedTimeSource(now: now)
        )
        capture.text = "chem test monday"

        await capture.extract()

        #expect(capture.stage == .writing)
        #expect(capture.text == "chem test monday")
        #expect(capture.failure != nil)
        #expect(capture.canSubmit, "manual entry must still be available")
    }

    @Test("the failure message never blames the user")
    func failureMessageIsNotJudgemental() async {
        let capture = CaptureViewModel(
            repository: InMemoryTaskRepository(),
            intelligence: AlwaysFailingIntelligence(),
            idProvider: SequentialIDProvider(),
            timeSource: FixedTimeSource(now: now)
        )
        capture.text = "chem test monday"

        await capture.extract()

        let message = (capture.failure ?? "").lowercased()
        for word in ["invalid", "you failed", "wrong", "bad", "error"] {
            #expect(!message.contains(word), "'\(word)' appears in: \(capture.failure ?? "")")
        }
    }
}

// MARK: - Doubles

private struct FailingRepository: TaskRepository {
    struct Failure: Error {}

    func fetchAll() async throws -> [TaskItem] { [] }
    func fetch(id: TaskID) async throws -> TaskItem? { nil }
    func fetch(status: TaskStatus) async throws -> [TaskItem] { [] }
    func upsert(_ task: TaskItem) async throws { throw Failure() }
    func upsert(_ tasks: [TaskItem]) async throws { throw Failure() }
    func delete(id: TaskID) async throws { throw Failure() }
}

private struct AlwaysFailingIntelligence: IntelligenceProvider {
    struct Unavailable: Error {}

    var supportedOperations: Set<IntelligenceOperation> { Set(IntelligenceOperation.allCases) }

    func extractTasks(_ request: TaskExtractionRequest) async throws -> Validated<TaskExtraction> {
        throw Unavailable()
    }
    func decompose(_ request: DecompositionRequest) async throws -> Validated<Decomposition> {
        throw Unavailable()
    }
    func nextAction(_ request: NextActionRequest) async throws -> Validated<ProposedAction> {
        throw Unavailable()
    }
    func estimateDuration(
        _ request: DurationEstimateRequest
    ) async throws -> Validated<DurationEstimate> {
        throw Unavailable()
    }
    func simplify(_ request: SimplificationRequest) async throws -> Validated<ProposedAction> {
        throw Unavailable()
    }
}
