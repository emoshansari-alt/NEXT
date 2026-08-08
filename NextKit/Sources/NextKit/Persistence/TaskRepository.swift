import Foundation

/// Everything the app is allowed to know about where tasks are kept.
///
/// The storage seam from ARCHITECTURE.md §3 and DECISIONS.md D-006. It traffics exclusively in
/// `TaskItem` value types — never a `ModelContext`, a managed object, a row, or any other
/// persistence-framework type. That is what keeps the domain layer compilable and testable on a
/// machine with no Xcode, and it is what makes a swap from SwiftData to Core Data a
/// one-module change.
///
/// ## Why the API is asynchronous
///
/// Nothing about an in-memory dictionary needs `async`. The SwiftData implementation in
/// `NextApp` does. SwiftData's `ModelContext` is not `Sendable` and is confined to whichever
/// actor owns it — `@MainActor` for the view context, or a `@ModelActor` for background work.
/// Reaching it from outside that actor is, by construction, an `await`.
///
/// A synchronous protocol would leave three options, all bad: pin every read to the main actor
/// and stutter the UI while a query runs; block a thread waiting on a semaphore, which
/// deadlocks under Swift concurrency's cooperative pool; or make the protocol lie and force the
/// implementation to cheat. Async is not speculative future-proofing here — it is the honest
/// signature of the only real implementation this project will have. It also costs the
/// in-memory version nothing, since an `actor` satisfies it naturally.
///
/// `throws` is untyped for the same reason: storage failures are the implementation's own
/// vocabulary — a corrupt store, a failed migration, a disk that is full — and `NextKit` has no
/// business enumerating them. The in-memory implementation simply never throws.
///
/// ## Ordering is part of the contract
///
/// Every list-returning method returns tasks **oldest first**, ties broken by identifier.
/// This is not a convenience. Ranking is a pure function of the list it is handed, so if the
/// store returned tasks in hash order the engine's tie-breaks — and therefore the single
/// recommendation on screen — could change between two launches with identical data. A store
/// that leaks its internal iteration order would quietly make the whole engine
/// non-deterministic.
public protocol TaskRepository: Sendable {

    /// Every task the store holds, in whatever state, oldest first.
    func fetchAll() async throws -> [TaskItem]

    /// The task with this identifier, or `nil` if there is none.
    ///
    /// A missing task is an ordinary answer, not a failure: the widget, a notification action
    /// and the app can all act on a snapshot that has since been deleted.
    func fetch(id: TaskID) async throws -> TaskItem?

    /// Every task in one lifecycle state, oldest first.
    ///
    /// This is what the Everything screen's sections and the ranking engine's input are built
    /// from, and it is a query the store can answer far more cheaply than the caller can by
    /// filtering everything.
    func fetch(status: TaskStatus) async throws -> [TaskItem]

    /// Stores a task, replacing any existing one with the same identifier.
    ///
    /// Insert and update are one operation because callers genuinely cannot tell the
    /// difference: a task edited on the Task Detail screen and a task arriving from a brain
    /// dump take the same path, and a caller forced to check first would race with itself.
    func upsert(_ task: TaskItem) async throws

    /// Stores several tasks as a single unit. **All of them land, or none of them do.**
    ///
    /// This exists for capture. A brain dump is one thought the user had, typed once, and a
    /// partial save is the worst possible outcome: four of their seven obligations are stored,
    /// three are gone, and nothing on screen says which. They would have to remember what they
    /// wrote in order to notice. All-or-nothing keeps the failure recoverable — nothing was
    /// saved, the text is still in the field, and they can try again.
    ///
    /// This is why it is a protocol requirement rather than a defaulted loop over `upsert`. A
    /// default implementation would be silently non-atomic, and every store would inherit
    /// exactly the behaviour this method exists to prevent.
    ///
    /// An empty array is a no-op. Later duplicates within the batch win, matching `upsert`.
    func upsert(_ tasks: [TaskItem]) async throws

    /// Removes a task. Removing one that is not there is a no-op, not an error.
    ///
    /// Idempotence matters because delete is reachable from more than one surface at once and
    /// from stale snapshots. A second delete must be harmless.
    func delete(id: TaskID) async throws
}
