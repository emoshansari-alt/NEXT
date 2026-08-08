import Foundation

/// Turns a task into the smallest meaningful *physical* action, and the ladder of actions
/// behind it.
///
/// This is the part of Rescue that has to be genuinely good. "Finish history essay" must
/// become "Open the assignment instructions." — an instruction that can be obeyed without
/// deciding anything first. A shrinker that answered "start the task" would satisfy the type
/// signature and be worth nothing.
///
/// The priority order is deliberate and is what the tests pin:
///
/// 1. **A recorded next action.** The user wrote it. Nothing inferred can beat it.
/// 2. **Outstanding substeps.** Real decomposition, in creation order.
/// 3. **A template for the inferred `WorkKind`.** A shallow keyword read of the title.
/// 4. **The generic ladder.** Honest, and honestly generic — better than confidently wrong.
///
/// Pure: no clock, no identifiers, no ambient state (DECISIONS.md D-007). Ordering never
/// depends on the order tasks arrive in.
public struct StepShrinker: Sendable {

    public init() {}

    /// The ordered ladder of physical steps for a task, smallest first.
    ///
    /// Never empty — a caller asking "what do I do" always gets an answer. `tasks` is the
    /// surrounding task list, used only to find substeps; passing nothing is fine.
    ///
    /// Note that this returns the *whole* ladder. Rescue itself reveals one rung at a time
    /// (PRODUCT_SPEC.md §4.11): showing the full decomposition to someone who is stuck
    /// rebuilds the mountain they came here to get away from.
    public func steps(for task: TaskItem, among tasks: [TaskItem] = []) -> [RescueStep] {
        var steps: [RescueStep] = []
        var seen: Set<String> = []

        func add(_ step: RescueStep) {
            guard seen.insert(Self.deduplicationKey(step.text)).inserted else { return }
            steps.append(step)
        }

        if let recorded = Self.instruction(from: task.nextAction) {
            add(RescueStep(text: recorded, origin: .recordedNextAction))
        }

        for child in Self.outstandingChildren(of: task, among: tasks) {
            let text = Self.instruction(from: child.nextAction)
                ?? Self.instruction(from: child.title)
            guard let text else { continue }
            add(
                RescueStep(
                    text: text,
                    origin: .substep(child.id),
                    estimatedMinutes: child.estimatedMinutes
                )
            )
        }

        guard steps.isEmpty else { return steps }

        if let kind = WorkKind.inferred(fromTitle: task.title) {
            return kind.firstSteps.map { RescueStep(text: $0, origin: .template(kind)) }
        }

        return Self.genericSteps
    }

    // MARK: - Substeps

    /// The task's own unfinished children, ordered oldest first and then by identifier.
    ///
    /// The identifier tie-break matters: two substeps created in the same brain dump share a
    /// creation instant, and without it the ladder would depend on array order, which is
    /// exactly the kind of hidden non-determinism D-007 exists to prevent.
    static func outstandingChildren(
        of task: TaskItem,
        among tasks: [TaskItem]
    ) -> [TaskItem] {
        tasks
            .filter { $0.parentID == task.id && $0.id != task.id && $0.status.isRecommendable }
            .sorted {
                $0.createdAt == $1.createdAt
                    ? $0.id.rawValue < $1.id.rawValue
                    : $0.createdAt < $1.createdAt
            }
    }

    // MARK: - Text

    /// Trims a raw string into a renderable instruction, or `nil` if there is nothing in it.
    ///
    /// A full stop is added when the text does not already end in punctuation, so that a
    /// user-typed substep like "Find one source" reads as an instruction alongside the
    /// generated ones. Nothing else about the user's wording is touched.
    static func instruction(from raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }

        guard let last = trimmed.last, !".!?".contains(last) else { return trimmed }
        return trimmed + "."
    }

    /// Case- and punctuation-insensitive key, so a substep that merely restates the recorded
    /// next action is not offered as though it were a second rung.
    private static func deduplicationKey(_ text: String) -> String {
        String(text.lowercased().filter(\.isLetter))
    }

    // MARK: - Fallbacks

    /// The step offered when the task says nothing useful about itself.
    ///
    /// It is deliberately about locating the instructions rather than about the work: when
    /// NEXT does not know what the task is, the one thing it can still be sure of is that the
    /// user knows where to look, and looking is physical.
    public static let genericFirstStep = RescueStep(
        text: "Find the instructions for this and open them.",
        origin: .generic
    )

    static let genericSteps: [RescueStep] = [
        genericFirstStep,
        RescueStep(text: "Write down the first thing it asks you to do.", origin: .generic),
        RescueStep(text: "Spend five minutes on that one thing.", origin: .generic)
    ]
}
