import Foundation
import SwiftData
import Testing

@testable import NextApp
import NextKit
import NextKitTestSupport

/// Tier 2. The schema survives being closed and reopened through the migration plan.
///
/// ## Why this exists while there is only one version
///
/// `RELEASE_CHECKLIST.md` requires a round-trip test per schema version before release-candidate
/// status, and it is tempting to read "one version, no stages" as "nothing to test". That is
/// wrong for two reasons.
///
/// The first is that `NextMigrationPlan` is on the real launch path — `NEXTApp.makeContainer()`
/// passes it for both the shipping store and the UI-testing one — and *nothing* had ever opened a
/// store through it twice. A plan that fails to open an existing store, or that quietly starts
/// from an empty one, is indistinguishable from a working plan on a first launch. It is only
/// distinguishable on the second, which is exactly where a user's whole task list is at stake.
///
/// The second is that this file is the harness V2 will need. When `StoredTask` moves inside each
/// `VersionedSchema` and a `MigrationStage` appears, the test that has to exist is "write at the
/// old version, open at the new one, assert every field survives". Writing that harness now, while
/// there is no migration to get wrong, means the V2 work starts from a test that already runs.
///
/// The tripwire at the bottom is what connects the two: adding a version without adding its round
/// trip fails the suite.
///
/// ## What "on disk" is doing here
///
/// Every assertion is against a real SQLite file in a throwaway directory, and one test asserts
/// the file is genuinely there. An in-memory container would pass every check in this suite while
/// proving nothing at all about reopening, which is the whole subject.
@Suite("Schema migration — the store survives being reopened")
struct SchemaMigrationTests {

    // MARK: The tasks under test

    /// Every field populated, including the ones that are optional, collection-shaped, or
    /// JSON-encoded — those are where a migration loses data quietly.
    private static func fullyPopulated() -> TaskItem {
        TaskItem(
            id: TaskID("chem"),
            title: "Chemistry worksheet",
            notes: "Questions 1 to 5, the ones on equilibrium.",
            createdAt: contractReference,
            updatedAt: contractHours(2),
            status: .completed,
            completedAt: contractHours(3),
            deadline: contractHours(24),
            importance: .important,
            estimatedMinutes: 25,
            nextAction: "Do questions 1 to 5.",
            prerequisiteIDs: [TaskID("reading"), TaskID("lab")],
            parentID: TaskID("coursework"),
            rejections: [
                Rejection(reason: .cantRightNow, at: contractHours(-4)),
                Rejection(reason: .needLessEffort, at: contractHours(-1))
            ],
            rejectionsSupersededAt: contractHours(-2)
        )
    }

    /// The opposite shape. A row where every optional is `nil` and every collection is empty is
    /// how a migration that writes a default over a legitimate absence gets caught.
    private static func sparse() -> TaskItem {
        TaskItem(id: TaskID("bare"), title: "Read chapter 4", createdAt: contractHours(-6))
    }

    // MARK: Tests

    @Test("every field survives closing the store and reopening it through the migration plan")
    func fieldsSurviveAReopen() async throws {
        let store = TemporaryStore()
        defer { store.remove() }

        let written = [Self.fullyPopulated(), Self.sparse()]
        try await store.write(written)

        // Not decoration. If the first phase had somehow used an in-memory container, everything
        // below would still pass — against a store this test had just created rather than one it
        // had reopened.
        #expect(
            FileManager.default.fileExists(atPath: store.url.path),
            "The store must be a real file on disk, or this suite proves nothing about reopening."
        )

        let recovered = try await store.read()

        // Whole-value equality is the assertion that actually catches an omission: `TaskItem`'s
        // `==` covers every stored property, so a field added later and dropped in migration
        // fails here without anyone remembering to add a line.
        #expect(recovered == written.sorted { $0.createdAt < $1.createdAt })
    }

    @Test("reopening repeatedly neither loses nor duplicates anything")
    func repeatedReopensAreIdempotent() async throws {
        let store = TemporaryStore()
        defer { store.remove() }

        let written = [Self.fullyPopulated(), Self.sparse()]
        try await store.write(written)

        // A migration stage that re-runs on every launch is a real failure mode, and it is
        // invisible on the launch that introduces it. Three opens, because the interesting
        // difference is between "runs once" and "runs every time".
        for _ in 0..<3 {
            let recovered = try await store.read()
            #expect(recovered.count == written.count)
        }

        let finalRead = try await store.read()
        #expect(finalRead == written.sorted { $0.createdAt < $1.createdAt })
    }

    @Test("a write made after a reopen lands in the same store, not a new one")
    func theStoreKeepsAcceptingWritesAfterAReopen() async throws {
        let store = TemporaryStore()
        defer { store.remove() }

        try await store.write([Self.sparse()])
        try await store.write([Self.fullyPopulated()])

        // Two separate containers, two separate sessions, one store. If the second open had
        // started somewhere else — a differently-derived path, a silently recreated file — this
        // reads one task rather than two.
        let recovered = try await store.read()
        #expect(recovered.count == 2)
        #expect(recovered.map(\.id) == [TaskID("bare"), TaskID("chem")])
    }

    @Test("the migration plan is the one the app launches with")
    func thePlanUnderTestIsTheShippingPlan() {
        // `NEXTApp.makeContainer()` passes `NextMigrationPlan` for the real store and for the
        // on-disk UI-testing store. A test that opened its container without the plan would be
        // testing a code path the app never takes, so this states the coupling rather than
        // leaving it to be noticed.
        //
        // Compared by `ObjectIdentifier` rather than with `is`: these are existential metatypes,
        // and identity is what is actually being asserted.
        let schemas = NextMigrationPlan.schemas.map { ObjectIdentifier($0) }
        let models = NextSchemaV1.models.map { ObjectIdentifier($0) }

        #expect(schemas == [ObjectIdentifier(NextSchemaV1.self)])
        #expect(models == [ObjectIdentifier(StoredTask.self)])
        #expect(NextSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    @Test("adding a schema version without a round trip for it fails here")
    func aNewVersionMustBringItsOwnRoundTrip() {
        // A tripwire, in the shape this project already uses for `emptyStoreIsSeeded`: the test
        // is meant to be *deleted and replaced* by whoever adds V2, not edited to keep passing.
        //
        // What they have to write is a round trip that opens a store written by the *previous*
        // version, which this suite cannot express while only one version exists — there is no
        // older shape to write. Failing here is how that requirement arrives at the moment it
        // becomes expressible instead of being remembered.
        #expect(
            NextMigrationPlan.schemas.count == 1,
            """
            A schema version was added. Before this passes again, write a round trip that writes \
            a store at the previous version and opens it at the new one, asserting every field \
            survives — RELEASE_CHECKLIST.md requires one per version.
            """
        )
        #expect(
            NextMigrationPlan.stages.isEmpty,
            """
            A migration stage was added. It needs a test that exercises it against a store \
            written by the schema it migrates from, not only against a store written by the \
            current one.
            """
        )
    }
}

/// A SwiftData store in a throwaway directory, opened exactly the way the app opens its own.
///
/// Each phase gets its own `ModelContainer` and lets it go, which is the point: SwiftData has no
/// close call, so "closed" here means the last reference is gone at the end of the call. Holding
/// one container for the whole test would keep the file open and turn a reopen into a re-read of
/// something already in memory.
private struct TemporaryStore {

    let url: URL

    init() {
        // Under the temporary directory, one directory per instance, so two tests running in the
        // same process cannot land on each other's database. A `UUID()` is fine here — D-007
        // forbids it in `NextKit`, and this is a Tier 2 test target.
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("next-migration-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("next.store")
    }

    /// Opens the store the same way `NEXTApp.makeContainer()` does, and hands back a repository.
    ///
    /// `ModelContainer` is `Sendable`; `ModelContext` is not, which is why nothing here reaches
    /// past the repository actor to touch a context directly.
    private func container() throws -> ModelContainer {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try ModelContainer(
            for: StoredTask.self,
            migrationPlan: NextMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
    }

    func write(_ tasks: [TaskItem]) async throws {
        let repository = SwiftDataTaskRepository(modelContainer: try container())
        try await repository.upsert(tasks)
    }

    func read() async throws -> [TaskItem] {
        let repository = SwiftDataTaskRepository(modelContainer: try container())
        return try await repository.fetchAll()
    }

    func remove() {
        // The write-ahead log and shared-memory files sit beside the database, so the directory
        // goes rather than the file — the same reason `NEXTApp` clears all three suffixes.
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
