import Foundation
import NextKit
import Observation

/// State for the Today screen — the app's primary surface.
///
/// It holds tasks in memory for now. The SwiftData-backed `TaskRepository` replaces that in
/// Phase 2; the view will not need to change, because it only ever reads `outcome`.
@MainActor
@Observable
final class TodayViewModel {

    /// What NEXT is currently recommending, or an explained reason there is nothing.
    private(set) var outcome: RecommendationOutcome

    /// The task the user is currently working on, if Focus is open.
    private(set) var focused: TaskItem?

    private(set) var tasks: [TaskItem]
    private let engine: RankingEngine

    /// `now` is injected rather than read inside, so the same recalculation logic the app
    /// runs is exactly what the tests exercise.
    init(
        tasks: [TaskItem],
        engine: RankingEngine = RankingEngine(),
        now: Date = Date()
    ) {
        self.tasks = tasks
        self.engine = engine
        self.outcome = engine.recommend(from: tasks, context: RankingContext(now: now))
    }

    /// The current recommendation, if there is one.
    var recommendation: Recommendation? { outcome.recommendation }

    // MARK: Intents

    func recalculate(now: Date = Date()) {
        outcome = engine.recommend(from: tasks, context: RankingContext(now: now))
    }

    /// START. Opens Focus on the recommended task.
    func startRecommended() {
        focused = outcome.recommendation?.task
    }

    func stopFocus() {
        focused = nil
    }

    /// DONE. Marks the focused task complete and immediately works out what is next —
    /// completion always flows straight back into the loop (PRODUCT_SPEC.md §4.10).
    func completeFocused(now: Date = Date()) {
        guard let focused else { return }
        apply(to: focused.id) { $0.status = .completed }
        self.focused = nil
        recalculate(now: now)
    }

    /// NOT THIS. Records the rejection so the engine demotes the task, then recalculates.
    func rejectRecommended(reason: RejectionReason, now: Date = Date()) {
        guard let task = outcome.recommendation?.task else { return }
        apply(to: task.id) { $0.rejections.append(Rejection(reason: reason, at: now)) }
        recalculate(now: now)
    }

    private func apply(to id: TaskID, _ change: (inout TaskItem) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[index])
    }
}
