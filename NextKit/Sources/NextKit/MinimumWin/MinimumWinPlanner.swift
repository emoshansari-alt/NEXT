import Foundation

/// Turns an unreachable goal into a ladder of goals that are not.
///
/// PRODUCT_SPEC.md §4.12: when the ideal outcome is no longer realistically achievable, NEXT
/// switches from *ideal completion* to *highest-value achievable progress*. A paper due
/// tonight becomes outline, then introduction, then first section, then reassess.
///
/// Three things this deliberately does not do.
///
/// - **It does not decide when to trigger.** `DeadlineFeasibility.unreachable` already exists
///   and `RankingEngine` already computes it; a second opinion here could disagree with the
///   recommendation the user is looking at. `plan(for:among:now:)` asks the engine, and
///   `plan(for:among:now:)` on a `Recommendation` uses the verdict it already carries.
/// - **It does not produce work.** Every rung is something the user does. Nothing here writes,
///   fills in, pads or supplies content — the academic-integrity boundary in PRODUCT_SPEC.md
///   §1 is enforced by what the copy says, and swept by `MinimumWinHonestyTests`.
/// - **It does not comment on the situation.** How the user ended up with two hours and six
///   hours of work is not the product's business (P5).
///
/// Pure: `now` is a parameter, there is no clock read, no identifier minted, and no dependence
/// on the order tasks arrive in (DECISIONS.md D-007).
public struct MinimumWinPlanner: Sendable {

    public let weights: MinimumWinWeights

    /// Consulted only for `feasibility(of:now:)` — the trigger. Nothing about ranking is
    /// reimplemented here.
    public let engine: RankingEngine

    public init(
        weights: MinimumWinWeights = .default,
        engine: RankingEngine = RankingEngine()
    ) {
        self.weights = weights
        self.engine = engine
    }

    // MARK: - Planning

    /// What is still achievable on this task, given the time left.
    public func plan(
        for task: TaskItem,
        among tasks: [TaskItem] = [],
        now: Date
    ) -> MinimumWinOutcome {
        plan(
            for: task,
            among: tasks,
            now: now,
            feasibility: engine.feasibility(of: task, now: now)
        )
    }

    /// The same, for a task the ranking engine has already judged.
    ///
    /// Uses the recommendation's own `deadlineFeasibility` rather than recomputing it, so the
    /// ladder can never contradict the screen that offered it.
    public func plan(
        for recommendation: Recommendation,
        among tasks: [TaskItem] = [],
        now: Date
    ) -> MinimumWinOutcome {
        plan(
            for: recommendation.task,
            among: tasks,
            now: now,
            feasibility: recommendation.deadlineFeasibility
        )
    }

    private func plan(
        for task: TaskItem,
        among tasks: [TaskItem],
        now: Date,
        feasibility: DeadlineFeasibility
    ) -> MinimumWinOutcome {
        guard feasibility.suggestsMinimumWin else { return .notNeeded(feasibility) }

        // A caller can hand in a feasibility of its own. An unreachable deadline on an undated
        // task is a contradiction, and the honest response to a contradiction is to decline
        // rather than to invent a deadline to plan against.
        guard let deadline = task.deadline else { return .notNeeded(.noDeadline) }

        let minutesRemaining = Int(deadline.timeIntervalSince(now) / 60)
        guard minutesRemaining > 0 else { return .noTimeRemaining }

        let (steps, source) = decomposition(of: task, among: tasks)
        let rungs = ladder(from: steps, within: minutesRemaining)

        guard let best = rungs.first else {
            // Unreachable: `decomposition` always yields at least one step, and one step
            // always yields at least the time-boxed rung.
            return .noTimeRemaining
        }

        return .ladder(
            MinimumWinPlan(
                taskID: task.id,
                taskTitle: task.title,
                minutesRemaining: minutesRemaining,
                source: source,
                framing: best.isTimeBoxed
                    ? .onlyAStartFits(minutesRemaining: minutesRemaining)
                    : .hereIsWhatFits(minutesRemaining: minutesRemaining),
                best: best,
                smallerRungs: Array(rungs.dropFirst()),
                reassessAt: now.addingTimeInterval(Double(best.minutes) * 60)
            )
        )
    }

    // MARK: - The ladder

    /// Turns a sequence of work into rungs, most ambitious first.
    ///
    /// Rung *k* is "the first *k* steps done", so its cost is the running total and the costs
    /// increase along the sequence. Finding what fits is therefore finding the longest prefix
    /// that fits, and everything shorter fits automatically — which is what makes "every rung
    /// fits" a property of the construction rather than a filter applied afterwards.
    private func ladder(from steps: [MinimumWinStep], within minutes: Int) -> [MinimumWinRung] {
        guard let first = steps.first else { return [] }

        var cumulative: [Int] = []
        var running = 0
        for step in steps {
            running += step.minutes
            cumulative.append(running)
        }

        guard let lastFitting = cumulative.lastIndex(where: { $0 <= minutes }) else {
            // Not even the first piece of work fits. Offer the window itself rather than an
            // empty screen: spending what is left on the first thing is real progress, and
            // the rung says outright that it does not finish.
            return [MinimumWinRung(goal: first, minutes: minutes, isTimeBoxed: true)]
        }

        return prefixLengths(upTo: lastFitting + 1).map { length in
            let included = Array(steps.prefix(length))
            return MinimumWinRung(
                goal: included[length - 1],
                leadingSteps: Array(included.dropLast()),
                minutes: cumulative[length - 1]
            )
        }
    }

    /// Which prefix lengths become rungs, longest first.
    ///
    /// When the sequence is short enough, every prefix is offered. When it is not, the picks
    /// are spread evenly from the whole thing down to the single first step, so the user gets
    /// a real choice of size rather than three near-identical options off the top.
    private func prefixLengths(upTo maximum: Int) -> [Int] {
        let limit = max(1, weights.maximumRungs)
        guard maximum > limit else { return Array((1...maximum).reversed()) }
        guard limit > 1 else { return [maximum] }

        let span = Double(maximum - 1)
        let picks = (0..<limit).map { step in
            1 + Int((Double(step) * span / Double(limit - 1)).rounded())
        }
        // Sorted, so the result cannot depend on set iteration order (D-007).
        return Set(picks).sorted(by: >)
    }

    // MARK: - Where the work comes from

    /// The sequence of work behind a task, and an honest label for where it came from.
    ///
    /// Recorded substeps win outright. They are the user's own decomposition of their own
    /// assignment; a keyword read of the title cannot beat that and should not try.
    private func decomposition(
        of task: TaskItem,
        among tasks: [TaskItem]
    ) -> ([MinimumWinStep], MinimumWinSource) {
        let substeps = substepSteps(of: task, among: tasks)
        if !substeps.isEmpty {
            return (substeps, .recordedSubsteps)
        }

        let kind = WorkKind.inferred(fromTitle: task.title)
        return (stageSteps(for: kind, estimate: task.estimatedMinutes), .genericStages(kind))
    }

    /// The task's outstanding children, in order, each with a length attached.
    ///
    /// Ordering is `StepShrinker`'s, deliberately: Rescue and Minimum Win must walk the same
    /// decomposition in the same order, or the app would contradict itself between two
    /// screens showing the same task.
    ///
    /// Empty when the task has no usable children — a child with a blank title and no next
    /// action names no work, so it is dropped rather than rendered as an empty rung.
    private func substepSteps(of task: TaskItem, among tasks: [TaskItem]) -> [MinimumWinStep] {
        let children = StepShrinker.outstandingChildren(of: task, among: tasks)
            .compactMap { child -> (task: TaskItem, text: String)? in
                let text = StepShrinker.instruction(from: child.nextAction)
                    ?? StepShrinker.instruction(from: child.title)
                return text.map { (child, $0) }
            }
        guard !children.isEmpty else { return [] }

        let allowance = allowancePerUntimedStep(
            among: children.map(\.task),
            total: task.estimatedMinutes
        )

        return children.map { child in
            let recorded = Self.recordedMinutes(of: child.task)
            return MinimumWinStep(
                text: child.text,
                minutes: recorded ?? allowance,
                origin: .substep(child.task.id),
                hasRecordedDuration: recorded != nil
            )
        }
    }

    /// How long to budget for a substep the user never timed.
    ///
    /// Whatever is left of the whole task's estimate once the timed substeps are accounted
    /// for, shared equally. This invents no new information: the one duration in the system
    /// came from the user, and this decides how it is divided. A step still gets the floor
    /// when the division leaves nothing, because a rung of zero minutes is not an offer.
    private func allowancePerUntimedStep(among children: [TaskItem], total: Int?) -> Int {
        let untimed = children.count { Self.recordedMinutes(of: $0) == nil }
        guard untimed > 0 else { return weights.minimumStageMinutes }

        let accounted = children.compactMap(Self.recordedMinutes).reduce(0, +)
        let pool = max(0, (total ?? 0) - accounted)

        return max(
            weights.minimumStageMinutes,
            Int((Double(pool) / Double(untimed)).rounded())
        )
    }

    /// A task's estimate, but only when it is a usable one.
    ///
    /// A zero or negative estimate is treated as no estimate rather than as a step that takes
    /// no time. Something the user has to do takes some time; storing otherwise is a data
    /// problem, and honouring it would produce a rung claiming work happens for free.
    private static func recordedMinutes(of task: TaskItem) -> Int? {
        guard let minutes = task.estimatedMinutes, minutes > 0 else { return nil }
        return minutes
    }

    /// The generic stage ladder, budgeted out of the estimate the user gave.
    private func stageSteps(for kind: WorkKind?, estimate: Int?) -> [MinimumWinStep] {
        let total = Double(max(0, estimate ?? 0))

        return MinimumWinStage.allCases.map { stage in
            MinimumWinStep(
                text: stage.instruction(for: kind),
                minutes: max(
                    weights.minimumStageMinutes,
                    Int((total * weights.share(for: stage)).rounded())
                ),
                origin: .stage(stage),
                hasRecordedDuration: false
            )
        }
    }
}
