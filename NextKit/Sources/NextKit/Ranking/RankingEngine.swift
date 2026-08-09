import Foundation

/// Decides what the user should do next.
///
/// This is the heart of NEXT and it is deliberately a **pure function**: given the same tasks,
/// the same context and the same `now`, it always returns the same answer. No clock reads, no
/// randomness, no I/O, no model call. A cloud LLM is never the decision-maker here
/// (PRODUCT_SPEC.md §5).
///
/// Ranking happens in two distinct stages, kept separate so that an empty result is always
/// explainable:
///
/// 1. **Filter** — discard tasks that are ineligible right now, remembering *why*.
/// 2. **Score** — rank whatever survives.
///
/// If the filter empties the list, the engine reports the reason rather than recommending
/// something ineligible or returning a bare nothing.
public struct RankingEngine: Sendable {

    public let weights: ScoringWeights

    public init(weights: ScoringWeights = .default) {
        self.weights = weights
    }

    // MARK: - Recommending

    /// Returns the single best thing to do now, or an explained reason there is nothing.
    public func recommend(
        from tasks: [TaskItem],
        context: RankingContext
    ) -> RecommendationOutcome {
        guard !tasks.isEmpty else { return .nothingToDo }

        // Stage 1a — only outstanding work is a candidate.
        let active = tasks.filter { $0.status.isRecommendable }
        guard !active.isEmpty else { return .nothingAvailable(.noActiveTasks) }

        // Stage 1b — a task waiting on unfinished prerequisites cannot be started.
        let unblocked = active.filter { !isBlocked($0, among: tasks) }
        guard !unblocked.isEmpty else { return .nothingAvailable(.everythingBlocked) }

        // Stage 1c — a stated time budget is a hard constraint.
        let fitting = unblocked.filter { $0.fits(withinMinutes: context.availableMinutes) }
        guard !fitting.isEmpty else {
            guard let shortest = unblocked.compactMap(\.estimatedMinutes).min() else {
                // Unreachable: a task can only be filtered here if it had an estimate.
                return .nothingAvailable(.noActiveTasks)
            }
            return .nothingAvailable(.nothingFitsAvailableTime(shortestMinutes: shortest))
        }

        // Stage 2 — score and rank the survivors.
        let ranked = fitting
            .map { (task: $0, score: score($0, among: tasks, context: context)) }
            .sorted { outranks($0, $1) }

        guard let best = ranked.first else {
            return .nothingAvailable(.noActiveTasks)
        }

        return .recommended(
            Recommendation(
                task: best.task,
                score: best.score,
                explanation: explain(
                    best.task, score: best.score, among: tasks, context: context
                ),
                deadlineFeasibility: feasibility(of: best.task, now: context.now),
                wasRecentlyRejected: rejectionDecay(for: best.task, now: context.now) > 0
            )
        )
    }

    // MARK: - Eligibility

    /// Whether a task is waiting on something unfinished.
    ///
    /// A prerequisite that cannot be found is treated as satisfied rather than blocking:
    /// dangling references must never strand a task where the user cannot reach it.
    func isBlocked(_ task: TaskItem, among tasks: [TaskItem]) -> Bool {
        guard !task.prerequisiteIDs.isEmpty else { return false }

        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return task.prerequisiteIDs.contains { id in
            guard let prerequisite = byID[id] else { return false }
            return prerequisite.status != .completed
        }
    }

    // MARK: - Scoring

    /// The full, itemised score for one task.
    ///
    /// Takes the whole task set because some factors are relational — how much a task unlocks
    /// can only be known by looking at what depends on it.
    public func score(
        _ task: TaskItem,
        among tasks: [TaskItem],
        context: RankingContext
    ) -> ScoreBreakdown {
        var factors: [RankingFactor: Double] = [:]

        // Every factor is written, including the ones that do not apply, so that a breakdown
        // is always complete. Absent must be spelled zero.
        for factor in RankingFactor.allCases {
            let signal = self.signal(for: factor, task: task, among: tasks, context: context)
            let contribution = signal * weights.weight(for: factor)
            factors[factor] = factor.isPenalty ? -contribution : contribution
        }

        return ScoreBreakdown(factors: factors)
    }

    /// The normalised `0...1` strength of one factor for one task.
    ///
    /// Keeping every factor on the same scale is what makes the weights in `ScoringWeights`
    /// meaningfully comparable to one another.
    private func signal(
        for factor: RankingFactor,
        task: TaskItem,
        among tasks: [TaskItem],
        context: RankingContext
    ) -> Double {
        switch factor {
        case .deadlineUrgency:
            urgencySignal(deadline: task.deadline, now: context.now)

        case .overdueRelevance:
            overdueSignal(deadline: task.deadline, now: context.now)

        case .importance:
            task.importance.signal

        case .contextualFit:
            contextualFitSignal(task: task, availableMinutes: context.availableMinutes)

        case .rejectionPenalty:
            rejectionDecay(for: task, now: context.now)

        case .unlockValue:
            unlockSignal(for: task, among: tasks)

        case .startability:
            task.hasConcreteNextAction ? 1 : 0

        // Deliberately zero, and decided rather than unfinished — see DECISIONS.md D-022.
        //
        // Every signal available for "harder to begin than its size suggests" is either already
        // counted by another factor or actively wrong. A missing first step is `startability`.
        // Recent refusals are `rejectionPenalty`. And the most tempting signal — that the task
        // has been started before and is still outstanding — would demote precisely the thing
        // the user is in the middle of, pushing them off work they had just begun.
        //
        // The factor stays present in every breakdown so "Why this?" cannot silently lose it,
        // and so introducing a real signal later is a change to this one expression.
        case .friction:
            0
        }
    }

    /// How much finishing this task would free up, from 0 (nothing depends on it) to 1
    /// (it gates `unlockSaturationCount` or more outstanding tasks).
    ///
    /// Only *outstanding* dependents count. Something already finished is not waiting on
    /// anything, so counting it would inflate the score of tasks that unblock nothing real.
    func unlockSignal(for task: TaskItem, among tasks: [TaskItem]) -> Double {
        let dependents = outstandingDependents(of: task, among: tasks)
        guard dependents > 0 else { return 0 }

        let saturation = max(1, weights.unlockSaturationCount)
        return min(1, Double(dependents) / Double(saturation))
    }

    func outstandingDependents(of task: TaskItem, among tasks: [TaskItem]) -> Int {
        tasks.count { candidate in
            candidate.status.isRecommendable && candidate.prerequisiteIDs.contains(task.id)
        }
    }

    /// How pressing a deadline is, from 0 (beyond the horizon, or undated) to 1 (due now or
    /// already past).
    private func urgencySignal(deadline: Date?, now: Date) -> Double {
        guard let deadline else { return 0 }

        let remaining = deadline.timeIntervalSince(now)
        // Past the deadline, urgency fades with the same curve lateness does. Holding it at full
        // strength is what let an abandoned task from last term outrank work that is still
        // achievable, for ever (DECISIONS.md D-020).
        guard remaining > 0 else { return latenessDecay(overdueBy: -remaining) }

        let horizon = weights.urgencyHorizon
        guard horizon > 0 else { return 1 }

        return max(0, min(1, 1 - remaining / horizon))
    }

    /// How much a passed deadline still counts for.
    private func overdueSignal(deadline: Date?, now: Date) -> Double {
        guard let deadline else { return 0 }

        let remaining = deadline.timeIntervalSince(now)
        guard remaining <= 0 else { return 0 }

        return latenessDecay(overdueBy: -remaining)
    }

    /// One curve, shared by both deadline factors.
    ///
    /// Deliberately a single function rather than a decay per factor: lateness is one idea, and
    /// two curves that could drift apart would make the ranking's behaviour past a deadline
    /// impossible to reason about — and only visible as a task mysteriously changing places.
    ///
    /// Full strength at the moment the deadline passes, falling linearly to `overdueFloor` over
    /// `overdueHorizon`, then flat. Flat rather than continuing to zero because the work is still
    /// outstanding: something that sank without limit would eventually be invisible, which is the
    /// app quietly deciding it no longer matters.
    private func latenessDecay(overdueBy: TimeInterval) -> Double {
        let floor = max(0, min(1, weights.overdueFloor))
        let horizon = weights.overdueHorizon
        guard horizon > 0 else { return floor }

        let travelled = min(1, max(0, overdueBy) / horizon)
        return 1 - travelled * (1 - floor)
    }

    /// How well a task uses the time the user actually has.
    ///
    /// Rewards filling the window. With 30 minutes free, a 30-minute task is a better use of
    /// the slot than a 5-minute one — the aim is the highest-value thing genuinely achievable,
    /// not merely the smallest thing that fits.
    ///
    /// Zero when the user has not stated a budget, so the factor stays neutral on the Today
    /// screen, which never asks.
    private func contextualFitSignal(task: TaskItem, availableMinutes: Int?) -> Double {
        guard
            let budget = availableMinutes, budget > 0,
            let estimate = task.estimatedMinutes, estimate > 0
        else { return 0 }

        return min(1, Double(estimate) / Double(budget))
    }

    /// How much a recent "Not this" still counts against a task, from 1 (just now) to
    /// 0 (the cooldown has elapsed, or it was never rejected).
    ///
    /// Driven by the most recent rejection the user has not already overridden, so rejecting a
    /// task again re-arms the full penalty. Anything from before `rejectionsSupersededAt` is
    /// ignored: the user started or reopened the task after saying "Not this", which settles
    /// the question more decisively than waiting out a cooldown. The records stay on the task —
    /// they are read by rejection rate, which is a tuning signal, not a punishment.
    ///
    /// The decay is linear and finite by design: a rejected task must be able to come back,
    /// because recommending nothing is worse than recommending something the user passed on an
    /// hour ago.
    func rejectionDecay(for task: TaskItem, now: Date) -> Double {
        guard let latest = task.latestActiveRejection else { return 0 }

        let cooldown = weights.rejectionCooldown
        guard cooldown > 0 else { return 0 }

        let elapsed = now.timeIntervalSince(latest.at)
        guard elapsed > 0 else { return 1 }

        return max(0, min(1, 1 - elapsed / cooldown))
    }

    // MARK: - Explaining

    /// Turns a score into the one sentence the user sees behind "Why this?".
    ///
    /// Overdue is checked before the numeric top factor. Urgency outweighs overdue in the
    /// scoring, so a mechanical "highest factor wins" rule would explain a two-day-late essay
    /// as "due soon" — technically derived from the score, and useless to the reader.
    /// Explanations are chosen for honesty, not for arithmetic tidiness.
    func explain(
        _ task: TaskItem,
        score: ScoreBreakdown,
        among tasks: [TaskItem],
        context: RankingContext
    ) -> ExplanationReason {
        if let deadline = task.deadline, deadline < context.now {
            return .overdue(by: context.now.timeIntervalSince(deadline))
        }

        guard let top = score.topPositiveContributors.first?.factor else {
            return .nothingElsePending
        }

        switch top {
        case .deadlineUrgency:
            guard let deadline = task.deadline else { return .nothingElsePending }
            return .dueSoon(within: deadline.timeIntervalSince(context.now))

        case .unlockValue:
            return .unlocksOtherWork(count: outstandingDependents(of: task, among: tasks))

        case .importance:
            return .markedImportant

        case .contextualFit:
            guard let minutes = context.availableMinutes else { return .nothingElsePending }
            return .fitsTheTimeYouHave(minutes: minutes)

        case .startability:
            return .hasAClearFirstStep

        case .overdueRelevance, .friction, .rejectionPenalty:
            return .nothingElsePending
        }
    }

    /// Whether the task can still be finished by its deadline.
    func feasibility(of task: TaskItem, now: Date) -> DeadlineFeasibility {
        guard let deadline = task.deadline else { return .noDeadline }
        guard let estimate = task.estimatedMinutes else { return .unknownDuration }

        let remaining = deadline.timeIntervalSince(now)
        let needed = Double(estimate) * 60

        if remaining < needed { return .unreachable }
        if remaining < needed * weights.tightDeadlineMultiplier { return .tight }
        return .comfortable
    }

    // MARK: - Ordering

    private typealias Scored = (task: TaskItem, score: ScoreBreakdown)

    /// A total ordering over scored tasks.
    ///
    /// It must be *total*, not merely a comparison: two tasks that score identically still
    /// have to resolve the same way on every call, regardless of the order they arrived in.
    /// Falling back to the identifier guarantees that, since identifiers are unique.
    private func outranks(_ lhs: Scored, _ rhs: Scored) -> Bool {
        let delta = lhs.score.total - rhs.score.total
        if abs(delta) > 1e-9 { return delta > 0 }

        // Equal scores: the nearer deadline first, undated last.
        switch (lhs.task.deadline, rhs.task.deadline) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            break
        }

        // Then the one the user has been carrying longest.
        if lhs.task.createdAt != rhs.task.createdAt {
            return lhs.task.createdAt < rhs.task.createdAt
        }

        return lhs.task.id.rawValue < rhs.task.id.rawValue
    }
}
