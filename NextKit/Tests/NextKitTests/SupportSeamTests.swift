import Foundation
import Testing

@testable import NextKit

// The determinism seams from ARCHITECTURE.md §3. NextKit ships the protocols and nothing else:
// a concrete time source would have to call Date() and a concrete provider would have to call
// UUID(), both banned by D-007. These tests therefore supply their own conformances, which is
// exactly how NextApp and the test suite are meant to use them.

// MARK: - Test conformances

/// A time source pinned to one instant. The production `SystemTimeSource` lives in `NextApp`.
///
/// Note the unqualified `TimeSource`: the seam is nameable without a module prefix from any
/// file that imports NextKit, which is the whole point of not calling it `Clock`.
private struct FixedTimeSource: TimeSource {
    let instant: Date
    var now: Date { instant }
}

/// Mints readable, ordered identifiers.
///
/// It is a reference type holding mutable state, so it has to synchronise itself — the
/// protocol is `Sendable` and `makeTaskID()` is non-mutating on purpose, so that the seam can
/// be passed around as `any IDProvider` and shared across concurrency domains.
private final class SequentialIDProvider: IDProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let prefix: String
    private var issued = 0

    init(prefix: String = "task") {
        self.prefix = prefix
    }

    func makeTaskID() -> TaskID {
        lock.lock()
        defer { lock.unlock() }
        issued += 1
        return TaskID("\(prefix)-\(issued)")
    }
}

/// The shape every caller of the seams actually has: neither time nor identity is reached for,
/// both arrive as arguments.
private func capture(
    _ title: String,
    time: any TimeSource,
    ids: any IDProvider
) -> TaskItem {
    TaskItem(id: ids.makeTaskID(), title: title, createdAt: time.now)
}

/// Names the *standard library's* `Clock` unqualified, from a file that imports NextKit.
///
/// This is the guard for the seam's name. While the seam was itself called `Clock` it shadowed
/// this declaration, so `C.Instant` did not resolve and `ContinuousClock` did not appear to
/// conform. Renaming the seam to `TimeSource` is what lets both protocols coexist unqualified.
private func instantType<C: Clock>(of _: C.Type) -> ObjectIdentifier {
    ObjectIdentifier(C.Instant.self)
}

// MARK: - Tests

@Suite("Support seams — TimeSource")
struct TimeSourceSeamTests {

    @Test("a time source reports the instant it was given, and keeps reporting it")
    func timeSourceIsStable() {
        let time = FixedTimeSource(instant: .testReference)

        #expect(time.now == .testReference)
        #expect(time.now == time.now)
    }

    @Test("a time source is usable as an existential, which is how it is injected")
    func timeSourceWorksAsExistential() {
        let time: any TimeSource = FixedTimeSource(instant: .hoursFromReference(3))

        #expect(time.now == .hoursFromReference(3))
    }

    @Test("the time seam does not shadow the standard library's Clock")
    func timeSourceDoesNotShadowStandardLibraryClock() {
        // Purely a name-resolution assertion — no instant is read, so nothing here is
        // time-dependent. If the seam were called `Clock` again this would not compile.
        #expect(instantType(of: ContinuousClock.self) == ObjectIdentifier(ContinuousClock.Instant.self))
        #expect(instantType(of: SuspendingClock.self) == ObjectIdentifier(SuspendingClock.Instant.self))
    }
}

@Suite("Support seams — IDProvider")
struct IDProviderSeamTests {

    @Test("every minted identifier is distinct")
    func identifiersAreDistinct() {
        let provider = SequentialIDProvider()

        let minted = (0..<100).map { _ in provider.makeTaskID() }

        #expect(Set(minted).count == 100)
    }

    @Test("a provider is usable as an existential, which is how it is injected")
    func providerWorksAsExistential() {
        let provider: any IDProvider = SequentialIDProvider(prefix: "chem")

        #expect(provider.makeTaskID() == TaskID("chem-1"))
        #expect(provider.makeTaskID() == TaskID("chem-2"))
    }

    @Test("concurrent minting still produces unique identifiers")
    func concurrentMintingIsUnique() async {
        let provider = SequentialIDProvider()

        let minted = await withTaskGroup(of: TaskID.self) { group in
            for _ in 0..<200 {
                group.addTask { provider.makeTaskID() }
            }
            var seen: Set<TaskID> = []
            for await id in group { seen.insert(id) }
            return seen
        }

        #expect(minted.count == 200)
    }
}

@Suite("Support seams — injection")
struct SupportSeamInjectionTests {

    @Test("a task can be built entirely from injected time and identity")
    func captureUsesOnlyInjectedSeams() {
        let time = FixedTimeSource(instant: .testReference)
        let ids = SequentialIDProvider(prefix: "dump")

        let first = capture("Chemistry worksheet", time: time, ids: ids)
        let second = capture("Email professor", time: time, ids: ids)

        #expect(first.id == TaskID("dump-1"))
        #expect(second.id == TaskID("dump-2"))
        #expect(first.createdAt == .testReference)
        #expect(second.createdAt == .testReference)
    }

    @Test("moving the time source moves creation time, and nothing else has to change")
    func creationTimeFollowsTheTimeSource() {
        let ids = SequentialIDProvider()

        let early = capture("A", time: FixedTimeSource(instant: .testReference), ids: ids)
        let late = capture("B", time: FixedTimeSource(instant: .daysFromReference(2)), ids: ids)

        #expect(early.createdAt < late.createdAt)
    }
}
