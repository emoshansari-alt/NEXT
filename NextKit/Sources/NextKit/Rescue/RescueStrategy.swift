import Foundation

/// Rescue: the four answers NEXT gives someone who is stuck.
///
/// This is the deterministic template layer. No model, no network, no clock read — it is what
/// the app falls back to when intelligence is unavailable, which is precisely why it has to
/// stand on its own (PRODUCT_SPEC.md §6, DECISIONS.md D-005).
///
/// The four paths deliberately behave differently:
///
/// | Path | What changes |
/// |---|---|
/// | `dontKnowHowToStart` | shrinks, and reveals one rung at a time |
/// | `tooMuch` | shrinks, hides the title and the existence of further rungs |
/// | `notEnoughTime` | ranks first, then shrinks to something that fits the window |
/// | `dontWantTo` | shrinks, and bounds the ask to a few minutes |
///
/// Ranking is not reimplemented here. The time path builds a `RankingContext` with
/// `availableMinutes` set and hands the decision to `RankingEngine`, so Rescue and the Today
/// screen can never disagree about what matters.
public struct RescueStrategy: Sendable {

    /// The size of the "tiny deal" offered by `dontWantTo`, in minutes.
    ///
    /// Five, from PRODUCT_SPEC.md §4.11. Small enough that refusing it costs more thought than
    /// accepting it, and bounded so that agreeing is not agreeing to the whole task. It lives
    /// here as one named constant rather than inline, for the same reason scoring constants
    /// live in `ScoringWeights` (ARCHITECTURE.md §10).
    public static let defaultCommitmentMinutes = 5

    public let commitmentMinutes: Int
    public let shrinker: StepShrinker
    public let engine: RankingEngine

    public init(
        commitmentMinutes: Int = RescueStrategy.defaultCommitmentMinutes,
        shrinker: StepShrinker = StepShrinker(),
        engine: RankingEngine = RankingEngine()
    ) {
        self.commitmentMinutes = commitmentMinutes
        self.shrinker = shrinker
        self.engine = engine
    }

    // MARK: - "I don't know how to start"

    /// Shrinks the task to its smallest physical action and reveals one rung of the ladder.
    ///
    /// `stepsAlreadyRevealed` is how many rungs the user has already seen, so the caller holds
    /// the progress and this stays a pure function. Out-of-range values are clamped rather
    /// than trapped: a stale value from a restored screen must not be able to crash Rescue.
    public func dontKnowHowToStart(
        with task: TaskItem,
        among tasks: [TaskItem] = [],
        stepsAlreadyRevealed: Int = 0
    ) -> RescueResponse {
        let ladder = ladder(for: task, among: tasks)
        let index = min(max(stepsAlreadyRevealed, 0), ladder.count - 1)

        return RescueResponse(
            path: .dontKnowHowToStart,
            taskID: task.id,
            taskTitle: task.title,
            framing: index == 0 ? .startHere : .thenThis,
            step: ladder[index],
            stepNumber: index + 1,
            hasMoreSteps: index < ladder.count - 1,
            commitmentMinutes: nil
        )
    }

    // MARK: - "It's too much"

    /// Takes the size of the task off the screen and offers its smallest known piece.
    ///
    /// Where `dontKnowHowToStart` walks the ladder in order, this reaches for whichever rung
    /// is *smallest*: the complaint is about size, so size decides. When no rung has a
    /// recorded length the earliest one is the small one, which is both the honest default
    /// and the same answer every time.
    ///
    /// A rung with no recorded length is not thereby enormous. Comparison happens only among
    /// rungs that actually state a size; an unrecorded one keeps its place in the ladder and
    /// is displaced only by a rung that is demonstrably smaller than it. Treating "unknown"
    /// as the largest possible number is how this path ends up handing back the mountain the
    /// user came here to get away from (PRODUCT_SPEC.md §4.11).
    public func tooMuch(with task: TaskItem, among tasks: [TaskItem] = []) -> RescueResponse {
        let ladder = ladder(for: task, among: tasks)
        let first = ladder[0]

        // Strictly less-than, so an equal-sized later rung never displaces an earlier one:
        // with no lengths recorded at all this degrades to "the first rung", deterministically.
        let smallestSized = ladder.reduce(nil as RescueStep?) { best, candidate in
            guard let size = candidate.estimatedMinutes else { return best }
            guard let bestSize = best?.estimatedMinutes else { return candidate }
            return size < bestSize ? candidate : best
        }

        // Only a size beats a position. Rung zero yields when it too states a size and that
        // size is the larger of the two; otherwise being first is what makes it the small one.
        let smallest: RescueStep
        if let candidate = smallestSized,
           let candidateSize = candidate.estimatedMinutes,
           let firstSize = first.estimatedMinutes,
           candidateSize < firstSize {
            smallest = candidate
        } else {
            smallest = first
        }

        return RescueResponse(
            path: .tooMuch,
            taskID: task.id,
            // Withheld on purpose. Naming the whole assignment is what made it a mountain.
            taskTitle: nil,
            framing: .forgetTheRestForNow,
            step: smallest,
            stepNumber: 1,
            // Also on purpose: "there are four more of these" is the mountain again.
            hasMoreSteps: false,
            commitmentMinutes: nil
        )
    }

    // MARK: - "I don't have enough time"

    /// Picks the highest-value action genuinely achievable in the window the user has.
    ///
    /// Two stages, and the first one is not Rescue's. `RankingEngine` chooses the task with
    /// `availableMinutes` set, which already treats the window as a hard constraint and
    /// already explains an empty result. Rescue then shrinks the winner to a rung that fits —
    /// necessary because a task with no estimate is eligible for any window, so "it fits"
    /// cannot be assumed just because the engine offered it.
    public func notEnoughTime(
        _ budget: TimeBudget,
        from tasks: [TaskItem],
        now: Date
    ) -> RescueOutcome {
        let context = RankingContext(now: now, availableMinutes: budget.minutes)

        switch engine.recommend(from: tasks, context: context) {
        case .nothingToDo:
            return .nothingToDo

        case .nothingAvailable(let reason):
            return .nothingAvailable(reason)

        case .recommended(let recommendation):
            let task = recommendation.task
            let ladder = ladder(for: task, among: tasks)

            // Rungs are walked in order and the first one that fits is taken. Order matters
            // more than filling the window here: a later rung usually depends on an earlier
            // one, so the biggest thing that fits is not necessarily a thing you can do yet.
            //
            // The two `nil` conventions are opposite on purpose, and both are stated rather
            // than smuggled in through a coercion. A rung of unknown length is offered — the
            // shrinker's job was to make it small, and refusing everything unmeasured would
            // leave this path with nothing to say. A *task* of unknown length is not declared
            // to fit, because claiming that would be inventing a measurement the user never
            // gave.
            let fitting = ladder.firstIndex {
                $0.estimatedMinutes.map { $0 <= budget.minutes } ?? true
            }
            let step = fitting.map { ladder[$0] } ?? StepShrinker.genericFirstStep
            let wholeTaskFits = task.estimatedMinutes.map { $0 <= budget.minutes } ?? false

            // Unlike "it's too much", this path already names the task, so it is not hiding
            // size and has no reason to deny that the ladder continues. Saying the whole
            // thing fits and then showing rung one of three without admitting the other two
            // is the response contradicting itself. The generic fallback is not a rung of
            // anything, so nothing follows it.
            let hasMoreSteps = fitting.map { $0 < ladder.count - 1 } ?? false

            return .guidance(
                RescueResponse(
                    path: .notEnoughTime,
                    taskID: task.id,
                    taskTitle: task.title,
                    framing: wholeTaskFits
                        ? .theWholeThingFits(minutes: budget.minutes)
                        : .oneStepInTheWindow(minutes: budget.minutes),
                    step: step,
                    // The rung actually on screen, not always the first. When the earlier rungs
                    // are too big for the window the one offered is further down the ladder, and
                    // `hasMoreSteps` is already computed from that real index — reporting step 1
                    // here would make the two fields describe different rungs. The generic
                    // fallback belongs to no ladder, so it is step 1 of one thing.
                    stepNumber: fitting.map { $0 + 1 } ?? 1,
                    hasMoreSteps: hasMoreSteps,
                    commitmentMinutes: budget.minutes
                )
            )
        }
    }

    // MARK: - "I just don't want to do it"

    /// Makes the ask smaller. That is the entire strategy.
    ///
    /// No diagnosis, no reason offered, no attempt to change how the user feels about the
    /// task — the product has no standing to do any of that, and doing it would be the
    /// productivity morality P5 forbids. What is left is friction: the deal is bounded, and
    /// the decision to continue is explicitly handed back afterwards.
    ///
    /// A task already shorter than the deal is offered whole. Asking for five minutes of a
    /// three-minute task would be theatre, and the user can see that it is.
    public func dontWantTo(with task: TaskItem, among tasks: [TaskItem] = []) -> RescueResponse {
        let ladder = ladder(for: task, among: tasks)
        let framing: RescueFraming
        let commitment: Int

        if let estimate = task.estimatedMinutes, estimate <= commitmentMinutes {
            framing = .theWholeThingIsShort(minutes: estimate)
            commitment = estimate
        } else {
            framing = .tinyDeal(minutes: commitmentMinutes)
            commitment = commitmentMinutes
        }

        return RescueResponse(
            path: .dontWantTo,
            taskID: task.id,
            taskTitle: task.title,
            framing: framing,
            step: ladder[0],
            stepNumber: 1,
            hasMoreSteps: false,
            commitmentMinutes: commitment
        )
    }

    // MARK: - Shared

    /// The task's ladder, guaranteed non-empty so the paths can index it without care.
    ///
    /// `StepShrinker` already promises this; the guard is here because a promise that only
    /// holds by inspection is one refactor away from a crash, and the substitute is a real
    /// step the user can actually follow rather than a placeholder.
    private func ladder(for task: TaskItem, among tasks: [TaskItem]) -> [RescueStep] {
        let steps = shrinker.steps(for: task, among: tasks)
        return steps.isEmpty ? [StepShrinker.genericFirstStep] : steps
    }
}
