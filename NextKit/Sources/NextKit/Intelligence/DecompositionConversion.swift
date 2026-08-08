import Foundation

extension Validated where Value == Decomposition {

    /// Turns a validated decomposition into real tasks belonging to `parent`.
    ///
    /// Steps become tasks rather than a separate `Substep` type on purpose. `StepShrinker` and
    /// `MinimumWinPlanner` already read a task's children through `parentID`, so breaking a
    /// task down immediately improves Rescue and Minimum Win too — instead of being a feature
    /// only one screen knows about. They are also independently rankable, which is the point:
    /// after a decomposition the engine can recommend a step rather than the mountain.
    ///
    /// Children inherit the deadline and importance because they *are* the same obligation. A
    /// step of something due Friday is due Friday; leaving children undated would tell the
    /// engine the real work has no urgency at all.
    ///
    /// Creation instants are staggered by a second each. The repository's ordering contract is
    /// oldest-first with ties broken by identifier, so identical instants would leave the rungs
    /// to be re-sorted alphabetically — and a decomposition is a ladder, not a set.
    public func childTasks(
        of parent: TaskItem,
        idProvider: any IDProvider,
        createdAt: Date
    ) -> [TaskItem] {
        let existingAction = parent.nextAction?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return value.steps
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            // The parent's recorded first step is usually the first thing a decomposition
            // produces. Storing it twice would show the user the same instruction on two rows.
            .filter { $0.lowercased() != existingAction }
            .enumerated()
            .map { index, text in
                TaskItem(
                    id: idProvider.makeTaskID(),
                    title: text,
                    createdAt: createdAt.addingTimeInterval(Double(index)),
                    deadline: parent.deadline,
                    importance: parent.importance,
                    estimatedMinutes: minutes(forStepAt: index, text: text),
                    parentID: parent.id
                )
            }
    }

    /// The estimate the provider gave for a step, matched back by position in the original list.
    private func minutes(forStepAt index: Int, text: String) -> Int? {
        value.steps.first {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == text
        }?.estimatedMinutes
    }
}

extension TaskItem {

    /// Records that this task cannot be finished until `children` are.
    ///
    /// The parent is the mountain. Once it has steps it has to stop competing with them for the
    /// recommendation, or breaking a task down would make the screen worse rather than better.
    /// Saying so as prerequisites reuses the blocking the ranking engine already does, and gives
    /// the steps unlock value for free.
    ///
    /// Additive and duplicate-free, so breaking the same task down twice adds the new steps
    /// without losing the old ones or listing anything twice.
    public func awaiting(_ children: [TaskItem]) -> TaskItem {
        var updated = self
        var seen = Set(prerequisiteIDs)

        for child in children where !seen.contains(child.id) {
            seen.insert(child.id)
            updated.prerequisiteIDs.append(child.id)
        }

        return updated
    }
}
