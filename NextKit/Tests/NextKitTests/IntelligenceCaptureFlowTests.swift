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

    @Test("breaking a task down under every failure mode leaves the task exactly as it was")
    func decompositionNeverDamagesTheParent() async throws {
        // Extraction was the only path either corruption test drove, and extraction is the safe
        // one: it can only ever mint new rows. Decomposition is the single place in NEXT where a
        // model's answer causes an *existing* task to be rewritten — the parent gains
        // prerequisites and a new `updatedAt` — so it is the only place a bad response could
        // damage something the user already had.
        //
        // Six of the eight modes apply to `.decompose`; the other two are shape-specific and say
        // so, which is checked here rather than assumed so a mode losing its applicability shows
        // up as a change in what this test covers.
        let parent = makeTask(
            id: "essay",
            title: "History essay",
            estimatedMinutes: 120,
            nextAction: "Open the assignment brief."
        )
        var covered: Set<IntelligenceFailureMode> = []

        for mode in IntelligenceFailureMode.allCases
        where mode.applicableOperations.contains(.decompose) {
            covered.insert(mode)

            let repository = InMemoryTaskRepository([parent])
            let provider = MockIntelligenceProvider(.failureMode(mode))

            do {
                let validated = try await provider.decompose(
                    DecompositionRequest(title: parent.title, estimatedMinutes: 120, maxSteps: 5)
                )
                let children = validated.childTasks(
                    of: parent, idProvider: ids, createdAt: .testReference
                )
                try await repository.upsert(children + [parent.awaiting(children)])
            } catch {
                // Expected for every mode. What matters is the store.
            }

            let stored = try await repository.fetchAll()
            #expect(stored == [parent], "\(mode)")
        }

        #expect(covered.count == 6)
    }

    @Test("a decomposition that succeeds does rewrite the parent")
    func aSuccessfulDecompositionChangesTheParent() async throws {
        // The control for the test above, and the reason it is not vacuous.
        //
        // "The store still equals what it started as" is only a meaningful assertion if this
        // write is capable of changing the store — otherwise both tests would pass against a
        // decomposition path that silently did nothing at all, and the guarantee would be an
        // artefact of broken plumbing rather than of the failure being contained.
        let parent = makeTask(id: "essay", title: "History essay", estimatedMinutes: 120)
        let repository = InMemoryTaskRepository([parent])

        let validated = try await TemplateFallbackProvider().decompose(
            DecompositionRequest(title: parent.title, estimatedMinutes: 120, maxSteps: 5)
        )
        let children = validated.childTasks(
            of: parent, idProvider: ids, createdAt: .testReference
        )
        try await repository.upsert(children + [parent.awaiting(children)])

        let stored = try await repository.fetchAll()
        #expect(stored != [parent])
        #expect(stored.count == children.count + 1)

        let rewritten = try #require(stored.first { $0.id == parent.id })
        #expect(rewritten.prerequisiteIDs == children.map(\.id))
    }

    @Test("nothing a provider returns can name a task the user already had")
    func providersCannotReachExistingTasks() async throws {
        // The guarantee proven here is about the *request*: there is no operation for editing,
        // completing or deleting, and no request type carries a `TaskID`, so a provider has no
        // way to name an existing task. Extraction only ever mints new identifiers.
        //
        // That is narrower than "an existing task can never be modified", which is not true —
        // decomposition rewrites the parent, deliberately and locally. The test above is the one
        // that covers that path.
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
