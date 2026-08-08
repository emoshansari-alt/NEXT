import Foundation

extension Validated where Value == TaskExtraction {

    /// Turns a validated extraction into tasks ready for the repository.
    ///
    /// This is the last few inches of the boundary, and it enforces one rule that nothing else
    /// can: **a field awaiting confirmation is not written**. A deadline the provider was 40%
    /// sure of stays out of the `TaskItem` entirely, so it cannot drive ranking, cannot schedule
    /// a notification, and cannot appear on the Today screen as though the user had said it.
    /// The proposal is still on the `Validated` value for Capture Confirmation to offer
    /// (PRODUCT_SPEC.md §4.6), and once the user accepts it, the app writes it as the user's own.
    ///
    /// The title is the exception, and deliberately: a low title confidence is flagged for
    /// editing, but blanking it would leave a row nobody could identify. A task with an
    /// uncertain name is still a task; a task with no name is a bug.
    ///
    /// Time and identity are parameters, as everywhere in `NextKit` (DECISIONS.md D-007). Every
    /// task from one dump shares a creation instant, which is why the repository's ordering
    /// contract breaks that tie by identifier.
    public func taskItems(idProvider: any IDProvider, createdAt: Date) -> [TaskItem] {
        value.tasks.enumerated().map { index, proposed in
            let unconfirmed = unconfirmedFields(ofItem: index)

            return TaskItem(
                id: idProvider.makeTaskID(),
                title: proposed.title,
                createdAt: createdAt,
                deadline: unconfirmed.contains(.deadline) ? nil : proposed.deadline?.date,
                importance: proposed.importance,
                estimatedMinutes: unconfirmed.contains(.estimatedMinutes)
                    ? nil
                    : proposed.duration?.minutes
            )
        }
    }
}
