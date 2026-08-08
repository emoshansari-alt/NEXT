import Foundation
import NextKit
import Observation

/// Capture — getting what is in the user's head into the app.
///
/// Two ways in, and the order matters. **Manual entry always works**: it needs no model, no
/// network and no extraction, and it is the fallback the whole product rests on (PRODUCT_SPEC.md
/// §6). Brain dump is the faster path when extraction can help.
///
/// Nothing is written until the user confirms. Extraction produces *proposals*; the user reviews
/// them; only then does anything reach the store. That is the rule from §4.6 — consequential
/// inferences, deadlines especially, are confirmable — and it is why the extracted tasks live in
/// `proposals` rather than being saved and corrected afterwards.
@MainActor
@Observable
final class CaptureViewModel {

    /// Where the user is in the capture flow.
    enum Stage: Equatable {
        /// Typing, either a single task or a dump.
        case writing

        /// Extraction produced tasks; the user is checking them.
        case confirming

        /// Everything was saved.
        case saved(count: Int)
    }

    private(set) var stage: Stage = .writing

    /// What the user typed. Kept on failure so nothing they wrote is ever lost.
    var text: String = ""

    /// The extracted tasks awaiting confirmation, editable in place.
    private(set) var proposals: [CaptureProposal] = []

    private(set) var isExtracting = false
    private(set) var failure: String?

    private let repository: any TaskRepository
    private let intelligence: any IntelligenceProvider
    private let idProvider: any IDProvider
    private let timeSource: any TimeSource

    init(
        repository: any TaskRepository,
        intelligence: any IntelligenceProvider = TemplateFallbackProvider(),
        idProvider: any IDProvider = UUIDProvider(),
        timeSource: any TimeSource = SystemTimeSource()
    ) {
        self.repository = repository
        self.intelligence = intelligence
        self.idProvider = idProvider
        self.timeSource = timeSource
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool { !trimmedText.isEmpty && !isExtracting }

    // MARK: Manual entry

    /// Saves exactly what the user typed, as one task, with no interpretation at all.
    ///
    /// No extraction, no model, no deadline guessing. The title is the text. This is the path
    /// that must keep working when everything cleverer is unavailable, so it deliberately shares
    /// none of the machinery below.
    func saveAsSingleTask() async {
        let title = trimmedText
        guard !title.isEmpty else { return }

        let task = TaskItem(
            id: idProvider.makeTaskID(),
            title: title,
            createdAt: timeSource.now
        )

        do {
            try await repository.upsert([task])
            text = ""
            failure = nil
            stage = .saved(count: 1)
        } catch {
            failure = "NEXT could not save that."
        }
    }

    // MARK: Brain dump

    /// Runs extraction and moves to confirmation. Writes nothing.
    func extract() async {
        let input = trimmedText
        guard !input.isEmpty else { return }

        isExtracting = true
        defer { isExtracting = false }

        do {
            let validated = try await intelligence.extractTasks(
                TaskExtractionRequest(text: input, now: timeSource.now, timeZone: .current)
            )
            proposals = CaptureProposal.from(validated, now: timeSource.now)
            failure = nil
            stage = .confirming
        } catch {
            // Extraction failing is not a dead end. The text is untouched and manual entry is
            // still right there, which is the whole point of the fallback rule.
            failure = "NEXT could not read that. You can still save it as one task."
        }
    }

    /// Writes the confirmed proposals. One dump is one write (`upsert(_ tasks:)`).
    func confirm() async {
        let kept = proposals.filter(\.isIncluded)
        guard !kept.isEmpty else { return }

        let now = timeSource.now
        let tasks = kept.map { $0.taskItem(id: idProvider.makeTaskID(), createdAt: now) }

        do {
            try await repository.upsert(tasks)
            text = ""
            proposals = []
            failure = nil
            stage = .saved(count: tasks.count)
        } catch {
            // Nothing was written — the batch is atomic — so the proposals stay exactly as they
            // were and the user can try again without retyping.
            failure = "NEXT could not save those. Nothing was lost — try again."
        }
    }

    /// Back to the text, with what they wrote intact.
    func returnToWriting() {
        stage = .writing
        proposals = []
    }

    // MARK: Editing proposals

    func setIncluded(_ included: Bool, forProposal id: CaptureProposal.ID) {
        update(id) { $0.isIncluded = included }
    }

    func setTitle(_ title: String, forProposal id: CaptureProposal.ID) {
        update(id) { $0.title = title }
    }

    func setDeadline(_ deadline: Date?, forProposal id: CaptureProposal.ID) {
        update(id) {
            $0.deadline = deadline
            // Editing a date is the user asserting it. It stops being a question.
            $0.deadlineNeedsConfirmation = false
        }
    }

    private func update(_ id: CaptureProposal.ID, _ change: (inout CaptureProposal) -> Void) {
        guard let index = proposals.firstIndex(where: { $0.id == id }) else { return }
        change(&proposals[index])
    }
}
