import Foundation
import Testing

@testable import NextKit

// The module in the position it actually occupies: between something typed into the Capture
// screen and the tasks the ranking engine ranks. Individual pieces are tested elsewhere; these
// tests exist to prove they compose, and that the composition still refuses to invent anything.

private let ids = SequentialIDs()

private func capture(
    _ text: String,
    with provider: any IntelligenceProvider,
    now: Date = .testReference
) async throws -> Validated<TaskExtraction> {
    try await provider.extractTasks(
        TaskExtractionRequest(text: text, now: now, timeZone: testTimeZone)
    )
}

@Suite("Capture flow — dump to recommendation, with no model")
struct CaptureFlowTests {

    @Test("a brain dump becomes tasks the ranking engine can rank")
    func dumpBecomesARecommendation() async throws {
        let validated = try await capture(
            "chem test monday, finish history slides friday, email professor",
            with: TemplateFallbackProvider()
        )

        let repository = InMemoryTaskRepository()
        for item in validated.taskItems(
            idProvider: SequentialIDs(), createdAt: .testReference
        ) {
            try await repository.upsert(item)
        }

        let outcome = RankingEngine().recommend(
            from: try await repository.fetchAll(),
            context: RankingContext(now: .testReference)
        )

        // No deadline survived unconfirmed, so nothing is urgent yet and the engine falls back
        // to its stable tie-break — but it still has something to recommend, which is the point.
        let recommendation = try #require(outcome.recommendation)
        #expect(!recommendation.task.title.isEmpty)
    }

    @Test("confirming a deadline is what makes it real")
    func confirmationIsWhatWritesTheDeadline() async throws {
        // The two halves of PRODUCT_SPEC.md §4.6 in one test. Before the user answers, the
        // deadline is a proposal and the stored task has none. After they answer, it is theirs.
        let validated = try await capture("chem test monday", with: TemplateFallbackProvider())

        let beforeConfirming = validated.taskItems(
            idProvider: SequentialIDs(), createdAt: .testReference
        )
        #expect(beforeConfirming[0].deadline == nil)

        let proposal = try #require(validated.value.tasks[0].deadline?.date)
        var confirmed = beforeConfirming[0]
        confirmed.deadline = proposal

        let outcome = RankingEngine().recommend(
            from: [confirmed], context: RankingContext(now: .testReference)
        )
        #expect(try #require(outcome.recommendation).task.deadline == proposal)
    }

    @Test("the confirmation screen has everything it needs to ask the question")
    func confirmationScreenHasWhatItNeeds() async throws {
        let validated = try await capture(
            "chem thing thurs and paper next friday", with: TemplateFallbackProvider()
        )

        for confirmation in validated.confirmations {
            let task = validated.value.tasks[confirmation.itemIndex]
            #expect(confirmation.field == .deadline)
            #expect(!task.title.isEmpty)
            #expect(task.deadline != nil)
        }
        #expect(validated.confirmations.count == 2)
    }
}

@Suite("Capture flow — when the model fails")
struct CaptureFallbackFlowTests {

    /// The recovery every caller performs: try the intelligent provider, and on any failure fall
    /// back to the deterministic one. Written out here rather than hidden behind a helper type,
    /// because the shape of it is what the test is about.
    private func captureWithFallback(
        _ text: String,
        preferring primary: any IntelligenceProvider
    ) async throws -> Validated<TaskExtraction> {
        do {
            return try await capture(text, with: primary)
        } catch {
            return try await capture(text, with: TemplateFallbackProvider())
        }
    }

    @Test("every failure mode still leaves the user with their tasks")
    func everyFailureModeStillCaptures() async throws {
        // PRODUCT_SPEC.md §6: NEXT stays useful when the provider is down, the response fails
        // validation, or there is no model at all. Not "degrades gracefully" — captures.
        for mode in IntelligenceFailureMode.allCases {
            let validated = try await captureWithFallback(
                "chem test monday, email professor",
                preferring: MockIntelligenceProvider(.failureMode(mode))
            )

            #expect(
                validated.value.tasks.map(\.title) == ["Chem test", "Email professor"],
                "\(mode)"
            )
        }
    }

    @Test("a declined consent is not an error the user has to see")
    func decliningIntelligenceStillCaptures() async throws {
        // PRIVACY.md: declining leaves a fully functional app.
        let validated = try await captureWithFallback(
            "chem test monday",
            preferring: MockIntelligenceProvider(.transportFailure(.unavailable(.consentNotGiven)))
        )

        #expect(validated.value.tasks.count == 1)
    }

    @Test("a working provider is not overridden by the fallback")
    func workingProviderIsUsed() async throws {
        let validated = try await captureWithFallback(
            "chem test monday",
            preferring: MockIntelligenceProvider(scripts: MockIntelligenceProvider.workingScripts)
        )

        // The scripted payload, not the template reading of the text.
        #expect(validated.value.tasks.map(\.title) == ["Chemistry worksheet"])
    }
}

@Suite("Capture flow — the database is never corrupted")
struct CaptureDatabaseIntegrityTests {

    @Test("a store seeded with real work survives every failure mode untouched")
    func existingWorkIsNeverDisturbed() async throws {
        // The strongest form of the guarantee in PRODUCT_SPEC.md §6, stated against a store that
        // already has something in it worth losing.
        let existing = [
            makeTask(id: "essay", title: "History essay", deadline: .daysFromReference(2)),
            makeTask(id: "chem", title: "Chemistry worksheet", estimatedMinutes: 30)
        ]

        for mode in IntelligenceFailureMode.allCases {
            let repository = InMemoryTaskRepository(existing)
            let provider = MockIntelligenceProvider(.failureMode(mode))

            do {
                let validated = try await capture("anything at all", with: provider)
                for item in validated.taskItems(idProvider: ids, createdAt: .testReference) {
                    try await repository.upsert(item)
                }
            } catch {
                // Expected for every mode. What matters is the store.
            }

            // Compared as a set: the repository imposes its own order (oldest first, then by
            // identifier), which is its contract and not this test's business.
            let stored = try await repository.fetchAll()
            #expect(Set(stored) == Set(existing), "\(mode)")
            #expect(stored.count == existing.count, "\(mode)")
        }
    }

    @Test("nothing a provider returns can change a task the user already had")
    func providersCannotReachExistingTasks() async throws {
        // There is no operation for editing, completing or deleting, and no request type carries
        // a `TaskID`, so a provider has no way to name an existing task at all. Extraction only
        // ever mints new identifiers.
        let repository = InMemoryTaskRepository([makeTask(id: "essay", title: "History essay")])

        let validated = try await capture("chem test monday", with: TemplateFallbackProvider())
        for item in validated.taskItems(idProvider: ids, createdAt: .testReference) {
            try await repository.upsert(item)
        }

        let stored = try await repository.fetchAll()
        #expect(stored.count == 2)
        #expect(stored.contains { $0.id == TaskID("essay") && $0.title == "History essay" })
    }
}
