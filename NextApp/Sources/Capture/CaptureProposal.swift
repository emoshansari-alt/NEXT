import Foundation
import NextKit

/// One extracted task, on its way to being confirmed.
///
/// A mutable editing shape, not a `TaskItem`. It exists precisely so that an inference the app
/// is unsure about can sit on screen as a *question* rather than as stored data. Nothing here
/// has been written; `taskItem(id:createdAt:)` is the only way anything becomes real.
struct CaptureProposal: Identifiable, Hashable {

    /// Stable only for the duration of the confirmation screen. The real `TaskID` is minted at
    /// save time, so abandoning the screen leaves no identifiers behind.
    let id: UUID

    var title: String
    var deadline: Date?
    var estimatedMinutes: Int?
    var importance: Importance

    /// Whether the user wants this one at all. Extraction is allowed to be wrong about how many
    /// things were in the text, and unticking is cheaper than deleting a task afterwards.
    var isIncluded: Bool

    /// The app inferred this deadline and is not confident enough to assert it.
    ///
    /// Drives the "is this right?" affordance in the UI. A deadline flagged this way is still
    /// shown — hiding it would waste a usable guess — but it is shown as a question, and it is
    /// never silently written as though the user had said it.
    var deadlineNeedsConfirmation: Bool

    /// The app inferred the title itself with low confidence, so it is worth a second look.
    var titleNeedsConfirmation: Bool

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether this proposal can actually be saved. A task with no name is not a task.
    var isSaveable: Bool { !trimmedTitle.isEmpty }

    func taskItem(id taskID: TaskID, createdAt: Date) -> TaskItem {
        TaskItem(
            id: taskID,
            title: trimmedTitle,
            createdAt: createdAt,
            deadline: deadline,
            importance: importance,
            estimatedMinutes: estimatedMinutes
        )
    }
}

extension CaptureProposal {

    /// Builds the editing list from a validated extraction.
    ///
    /// Reads `unconfirmedFields(ofItem:)` rather than re-deriving confidence: the validator has
    /// already decided what is certain enough to assert, and having two places make that
    /// judgement is how they come to disagree.
    ///
    /// Note the deliberate difference from `Validated.taskItems(idProvider:createdAt:)`, which
    /// *drops* an unconfirmed deadline so it can never reach storage. Here the value is kept and
    /// marked, because this screen exists to ask about it. Same rule — nothing uncertain is
    /// written — reached from opposite ends.
    static func from(_ validated: Validated<TaskExtraction>, now: Date) -> [CaptureProposal] {
        validated.value.tasks.enumerated().map { index, proposed in
            let unconfirmed = validated.unconfirmedFields(ofItem: index)

            return CaptureProposal(
                id: UUID(),
                title: proposed.title,
                deadline: proposed.deadline?.date,
                estimatedMinutes: proposed.duration?.minutes,
                importance: proposed.importance,
                isIncluded: true,
                deadlineNeedsConfirmation: unconfirmed.contains(.deadline),
                titleNeedsConfirmation: unconfirmed.contains(.title)
            )
        }
    }
}
