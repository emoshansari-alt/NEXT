import Foundation

/// Where the action in front of the user came from.
public enum FocusOrigin: Hashable, Sendable {

    /// The task's own next action, as the ranking engine offered it.
    case recommendation

    /// A step Rescue shrank the task down to.
    case rescue(RescuePath)

    /// A rung from the Minimum Win ladder, chosen because the whole outcome no longer fits.
    case minimumWin

    /// Whether this is a deliberately smaller piece of the task rather than the task itself.
    ///
    /// The distinction decides what finishing means, so it is stated per case rather than
    /// derived from anything incidental. A future origin has to answer this question on purpose.
    public var isReduced: Bool {
        switch self {
        case .recommendation: false
        case .rescue, .minimumWin: true
        }
    }
}

/// What Focus is pointed at.
///
/// This exists because of a defect that shipped: Rescue would shrink "History essay" down to
/// "Open the assignment instructions.", the user would tap "Do that", and Focus would open on
/// *the essay* — the same mountain they had just said was too much. The step was computed,
/// displayed, and then dropped on the way to the screen meant to act on it.
///
/// Passing a bare `TaskItem` to Focus is what made that possible, because a task can only ever
/// describe itself. A target carries the task *and* the action, so a reduced action survives the
/// journey and the screen cannot silently fall back to the whole thing.
///
/// It lives in `NextKit` rather than in a view because every rule here is about propagation —
/// which task, which words, and what finishing means — and those are exactly the rules that are
/// invisible in a screenshot and expensive to check on a Simulator.
public struct FocusTarget: Hashable, Sendable, Identifiable {

    /// The task the work belongs to.
    public let task: TaskItem

    /// The single thing to do right now.
    public let action: String

    /// The parent task's name, when showing it adds something.
    ///
    /// `nil` in two quite different cases, both deliberate: when it would merely repeat the
    /// action, and when the path that produced the action withheld it on purpose.
    public let parentTitle: String?

    public let origin: FocusOrigin

    /// Identity is the task, not the action, so changing the action while Focus is open updates
    /// the screen in place instead of dismissing and re-presenting it. That is what makes the
    /// Focus → stuck → smaller action → Focus loop feel like one continuous session.
    public var id: TaskID { task.id }

    public init(task: TaskItem, action: String, parentTitle: String?, origin: FocusOrigin) {
        self.task = task
        self.action = action
        self.parentTitle = parentTitle
        self.origin = origin
    }

    /// Whether this is a smaller piece of the task rather than the whole of it.
    public var isReduced: Bool { origin.isReduced }

    /// Whether finishing this finishes the task.
    ///
    /// **False for every reduced action, and that is the point.** Someone who spent five minutes
    /// opening the assignment instructions has not written the essay. Marking it complete would
    /// destroy work the app cannot give back, and would contradict the reason the smaller step
    /// was offered in the first place.
    public var completesTask: Bool { !isReduced }

    // MARK: - Building one

    /// The ordinary case: the task as the ranking engine offered it.
    public init(recommending task: TaskItem) {
        let recorded = task.nextAction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = (recorded?.isEmpty == false ? recorded : nil) ?? task.title

        self.init(
            task: task,
            action: action,
            // Context when it adds something, nothing when it would say the same thing twice on
            // a screen whose whole job is to show one thing.
            parentTitle: action == task.title ? nil : task.title,
            origin: .recommendation
        )
    }

    /// The step Rescue offered, pointed at the task Rescue named.
    ///
    /// Resolves the task from `response.taskID` rather than taking one on trust. The
    /// "I don't have enough time" path re-ranks against the stated window and can legitimately
    /// come back about a *different* task, so assuming the answer concerns whatever was on screen
    /// would open Focus on the wrong work while displaying the right words.
    ///
    /// Returns `nil` when that task no longer exists, which is reachable: the store can change
    /// underneath a sheet. Refusing is better than focusing something arbitrary.
    public static func rescued(
        _ response: RescueResponse,
        among tasks: [TaskItem]
    ) -> FocusTarget? {
        guard let task = tasks.first(where: { $0.id == response.taskID }) else { return nil }

        return FocusTarget(
            task: task,
            action: response.step.text,
            // Taken from the response, not from the task. "It's too much" withholds the title on
            // purpose — naming the mountain is what made it too much — and Focus re-deriving it
            // from the task would quietly undo the only thing that path does.
            parentTitle: response.taskTitle,
            origin: .rescue(response.path)
        )
    }

    /// A rung the user chose from the Minimum Win ladder.
    public static func minimumWin(
        _ rung: MinimumWinRung,
        in plan: MinimumWinPlan,
        among tasks: [TaskItem]
    ) -> FocusTarget? {
        guard let task = tasks.first(where: { $0.id == plan.taskID }) else { return nil }

        return FocusTarget(
            task: task,
            action: rung.goal.text,
            // Shown here, unlike Rescue's hiding path: the user has not asked for the size of the
            // thing to be hidden, they have asked what is still possible.
            parentTitle: plan.taskTitle,
            origin: .minimumWin
        )
    }
}
