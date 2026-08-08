import Foundation
import NextKit
import Observation

/// State for the Today screen — the app's primary surface.
///
/// It owns no task data of its own. Every read comes from the repository and every change is
/// written back through it before the screen updates, so the store is the single source of
/// truth and a task cannot exist only in the UI.
///
/// `now` comes from an injected `TimeSource` rather than from `Date()`, so a test can place the
/// whole screen at a fixed instant and assert on deadline behaviour exactly.
@MainActor
@Observable
final class TodayViewModel {

    /// What NEXT is currently recommending, or an explained reason there is nothing.
    private(set) var outcome: RecommendationOutcome = .nothingToDo

    /// The task the user is working on, if Focus is open.
    private(set) var focused: TaskItem?

    /// Set when the store could not be read or written.
    ///
    /// Surfaced rather than swallowed. A silent failure here would show the user an empty
    /// Today screen and let them believe their work was gone.
    private(set) var storeFailure: String?

    private let repository: any TaskRepository
    private let engine: RankingEngine
    private let timeSource: any TimeSource

    init(
        repository: any TaskRepository,
        engine: RankingEngine = RankingEngine(),
        timeSource: any TimeSource = SystemTimeSource()
    ) {
        self.repository = repository
        self.engine = engine
        self.timeSource = timeSource
    }

    /// The current recommendation, if there is one.
    var recommendation: Recommendation? { outcome.recommendation }

    // MARK: Loading

    /// Reads the store and works out what to do next.
    ///
    /// Seeds sample tasks when the store is empty. **That is temporary**: capture does not exist
    /// yet, so without it a first run is a dead end with nothing to add and nothing to do. It
    /// goes when Phase 5 lands and a genuine first run shows the empty state.
    func load() async {
        do {
            var tasks = try await repository.fetchAll()

            if tasks.isEmpty {
                for task in SampleTasks.starter(now: timeSource.now) {
                    try await repository.upsert(task)
                }
                tasks = try await repository.fetchAll()
            }

            outcome = engine.recommend(from: tasks, context: context())
            storeFailure = nil
        } catch {
            storeFailure = "NEXT could not open your tasks."
            outcome = .nothingToDo
        }
    }

    // MARK: Intents

    /// START. Opens Focus on the recommended task and records that the user chose it, which
    /// supersedes any earlier "Not this" (`TaskItem.rejectionsSupersededAt`).
    func startRecommended() async {
        guard let task = outcome.recommendation?.task else { return }

        focused = task
        await write { try task.started(at: self.timeSource.now) }
    }

    func stopFocus() {
        focused = nil
    }

    /// DONE. Completion always flows straight back into the loop (PRODUCT_SPEC.md §4.10).
    func completeFocused() async {
        guard let task = focused else { return }

        focused = nil
        await write { try task.completed(at: self.timeSource.now) }
    }

    /// NOT THIS. Records the rejection so the engine demotes the task, then recalculates.
    func rejectRecommended(reason: RejectionReason) async {
        guard let task = outcome.recommendation?.task else { return }

        await write { try task.rejected(reason, at: self.timeSource.now) }
    }

    // MARK: Plumbing

    /// Applies a transition, persists it, and recomputes the recommendation from the store.
    ///
    /// Recalculating from a fresh read rather than from a local copy is deliberate: the widget
    /// and notification actions can change the same store, so the screen should reflect what is
    /// actually saved rather than what this object last believed.
    private func write(_ transition: () throws -> TaskItem) async {
        do {
            try await repository.upsert(transition())
            outcome = engine.recommend(from: try await repository.fetchAll(), context: context())
            storeFailure = nil
        } catch {
            storeFailure = "NEXT could not save that change."
        }
    }

    private func context() -> RankingContext {
        RankingContext(now: timeSource.now)
    }
}
