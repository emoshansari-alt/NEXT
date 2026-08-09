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

    /// What the user is working on, if Focus is open.
    ///
    /// A `FocusTarget` rather than a `TaskItem` because Focus is not always pointed at a whole
    /// task: Rescue and Minimum Win both hand back a deliberately smaller action, and a bare task
    /// cannot carry one. That is not a hypothetical — a rescued step used to be computed, shown,
    /// and then dropped here, so "Do that" opened Focus on the mountain the user had just said
    /// was too much.
    private(set) var focus: FocusTarget?

    /// What is still achievable on the recommended task, when the whole of it no longer is.
    ///
    /// `nil` unless there is genuinely a ladder to offer, which is most of the time. Stored
    /// rather than computed on demand for two reasons: the planner reads the clock, so a computed
    /// version would change under SwiftUI without anything telling it to re-render, and a view
    /// body touches this several times per pass. It is recomputed wherever `outcome` is, from the
    /// recommendation's own `deadlineFeasibility` rather than a fresh judgement — so the ladder
    /// can never contradict the screen that offered it (PRODUCT_SPEC.md §4.12).
    private(set) var minimumWinPlan: MinimumWinPlan?

    /// Everything currently in the store.
    ///
    /// Exposed because Rescue needs the whole set, not just the recommendation: the
    /// "I don't have enough time" path re-ranks against a stated window, and the shrinking
    /// paths need a task's substeps, which are separate tasks linked by `parentID`.
    private(set) var tasks: [TaskItem] = []

    /// A task opened from a widget tap or a notification.
    private(set) var linkedTask: TaskItem?

    /// Set when the store could not be read or written.
    ///
    /// Surfaced rather than swallowed. A silent failure here would show the user an empty
    /// Today screen and let them believe their work was gone.
    private(set) var storeFailure: String?

    private let repository: any TaskRepository
    private let engine: RankingEngine
    private let planner: MinimumWinPlanner
    private let timeSource: any TimeSource

    /// Called after anything is written.
    ///
    /// Reminders are planned from the whole task list, so completing something has to cancel
    /// its reminder — otherwise NEXT would notify a student about work they finished this
    /// morning, which is the clearest possible sign an app is not paying attention.
    private let onStoreChanged: () async -> Void

    /// Writes what the widget shows. `nil` in tests that do not care about it.
    private let snapshotPublisher: SnapshotPublisher?

    init(
        repository: any TaskRepository,
        engine: RankingEngine = RankingEngine(),
        timeSource: any TimeSource = SystemTimeSource(),
        snapshotPublisher: SnapshotPublisher? = nil,
        onStoreChanged: @escaping () async -> Void = {}
    ) {
        self.repository = repository
        self.engine = engine
        // Built from the same engine, so the ladder's trigger and the screen's verdict are one
        // judgement rather than two that can disagree.
        self.planner = MinimumWinPlanner(engine: engine)
        self.timeSource = timeSource
        self.snapshotPublisher = snapshotPublisher
        self.onStoreChanged = onStoreChanged
    }

    /// The current recommendation, if there is one.
    var recommendation: Recommendation? { outcome.recommendation }

    // MARK: Loading

    /// Reads the store and works out what to do next.
    ///
    /// A first run genuinely shows the empty state now. Sample seeding lived here while capture
    /// did not exist, because an empty app with no way to add anything was a dead end; Phase 5
    /// removed both it and the test that was guarding against forgetting to.
    func load() async {
        do {
            recompute(from: try await repository.fetchAll())
            storeFailure = nil
            publishSnapshot()
        } catch {
            storeFailure = "NEXT could not open your tasks."
            outcome = .nothingToDo
            minimumWinPlan = nil
        }
    }

    /// Everything derived from the store, worked out in one place.
    ///
    /// Both the recommendation and the Minimum Win ladder are recomputed together, from the same
    /// list at the same instant. Deriving them at different moments is how a screen ends up
    /// offering a reduced goal for a task it is no longer recommending.
    private func recompute(from stored: [TaskItem]) {
        tasks = stored
        outcome = engine.recommend(from: stored, context: context())
        minimumWinPlan = outcome.recommendation.flatMap {
            planner.plan(for: $0, among: stored, now: timeSource.now).plan
        }
    }

    /// Keeps the widget showing what Today shows.
    ///
    /// Not published on a store failure: the widget should keep its last good answer rather than
    /// be blanked because a read failed once. It goes stale on its own after a day.
    private func publishSnapshot() {
        snapshotPublisher?.publish(outcome, at: timeSource.now)
    }

    // MARK: Intents

    /// START. Opens Focus on the recommended task and records that the user chose it, which
    /// supersedes any earlier "Not this" (`TaskItem.rejectionsSupersededAt`).
    func startRecommended() async {
        guard let task = outcome.recommendation?.task else { return }

        focus = FocusTarget(recommending: task)
        await write { try task.started(at: self.timeSource.now) }
    }

    /// "Do that" — the user accepted the smaller step Rescue offered.
    ///
    /// The task is resolved from the response rather than from whatever is on screen, because the
    /// "I don't have enough time" path re-ranks and can legitimately answer about a different
    /// task. `FocusTarget.rescued` does that lookup and refuses rather than guessing when the
    /// task is gone.
    func focusRescued(_ response: RescueResponse) async {
        guard let target = FocusTarget.rescued(response, among: tasks) else { return }

        focus = target
        let task = target.task
        await write { try task.started(at: self.timeSource.now) }
    }

    /// The user picked a rung from the Minimum Win ladder.
    func focusMinimumWin(_ rung: MinimumWinRung, in plan: MinimumWinPlan) async {
        guard let target = FocusTarget.minimumWin(rung, in: plan, among: tasks) else { return }

        focus = target
        let task = target.task
        await write { try task.started(at: self.timeSource.now) }
    }

    func stopFocus() {
        focus = nil
    }

    /// Handles a widget tap or a notification tap.
    ///
    /// A link to a task that has since been deleted resolves to nothing and simply leaves the
    /// user on Today. That is reachable in normal use — a widget can be several minutes stale,
    /// and a reminder can outlive the thing it was about — so it must not be an error.
    func open(_ link: DeepLink) async {
        switch link {
        case .today:
            linkedTask = nil
            await load()

        case .task(let id):
            linkedTask = try? await repository.fetch(id: id)
        }
    }

    func closeLinkedTask() {
        linkedTask = nil
    }

    /// DONE. Completion always flows straight back into the loop (PRODUCT_SPEC.md §4.10).
    ///
    /// **A reduced action does not complete its task.** Someone who spent five minutes opening
    /// the assignment instructions has not written the essay, and marking it done would destroy
    /// work the app cannot give back. Rescue and Minimum Win both exist precisely because the
    /// whole thing is not what is happening right now.
    ///
    /// What is recorded in that case is what was already recorded when Focus opened: the task was
    /// started, which supersedes any earlier rejection. Nothing further is invented. D-018
    /// considered recording the finished step as a completed child task and decided against it
    /// for 1.0 — the benefit only arrives with a change to `StepShrinker`, and without that it
    /// would add an entry to every user's completed list and buy nothing they would notice.
    func completeFocused() async {
        guard let target = focus else { return }

        focus = nil

        guard target.completesTask else {
            // Straight back into the loop, same as a completion: the store may have changed and
            // the next recommendation is computed from a fresh read.
            await load()
            return
        }

        let task = target.task
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
            recompute(from: try await repository.fetchAll())
            storeFailure = nil
            publishSnapshot()
            await onStoreChanged()
        } catch {
            storeFailure = "NEXT could not save that change."
        }
    }

    private func context() -> RankingContext {
        RankingContext(now: timeSource.now)
    }
}
