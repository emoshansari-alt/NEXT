import Foundation

// The state changes a task can go through, as pure functions.
//
// Every transition takes the task it is called on, an instant, and nothing else. It returns a
// new `TaskItem` and mutates nothing — so the whole
// CAPTURE → DECIDE → START → FINISH → NEXT loop can be replayed in a test with no store, no
// clock and no UI, and so a caller always has both the before and after value in hand.

/// Why a state change was refused.
///
/// These are **developer diagnostics**, not user-facing copy. Nothing on screen is derived from
/// them: a refusal means a caller asked for something the data does not permit, which is a
/// programming or staleness problem, never something to tell the user about themselves.
/// `TaskTransitionRefusalTests` asserts they stay free of any language that could read as a
/// judgement, in case one ever leaks into a log or a debug surface (PRODUCT_SPEC.md P5).
public enum TaskTransitionError: Error, Hashable, Sendable {

    /// The transition needs an outstanding task, and this one is finished or filed away.
    /// Carries the state that caused the refusal so the caller can react precisely — offering
    /// "reopen", say, rather than a generic failure.
    case notActive(TaskStatus)

    /// Nothing to reopen: the task is already outstanding.
    case alreadyActive

    /// Nothing to archive: the task is already filed away.
    case alreadyArchived

    /// A next action made only of whitespace. Storing it would make the task look startable
    /// while leaving the user with nothing to actually do.
    case emptyNextAction
}

extension TaskTransitionError: CaseIterable {

    /// Every refusal the transitions can produce.
    ///
    /// Hand-written because `notActive` carries a payload. It exists so tests can sweep the
    /// complete set rather than a list someone has to remember to update.
    public static var allCases: [TaskTransitionError] {
        TaskStatus.allCases.map { .notActive($0) }
            + [.alreadyActive, .alreadyArchived, .emptyNextAction]
    }
}

extension TaskItem {

    // MARK: - Lifecycle

    /// The user has begun this task — they tapped START and Focus opened.
    ///
    /// Any recorded "Not this" is discarded. The rejection penalty exists to stop NEXT
    /// re-offering something the user just turned down; once they have chosen the task
    /// themselves that penalty is stale, and leaving it in place would suppress the very thing
    /// they are working on from being recommended again after a pause.
    ///
    /// The status does not change. Starting is not a stored state — a task being worked on
    /// right now is still outstanding, and inventing an `inProgress` state would create a
    /// fourth thing that can go out of sync with reality when the app is killed mid-Focus.
    public func started(at now: Date) throws -> TaskItem {
        try requireActive()

        var updated = self
        updated.rejections = []
        return updated
    }

    /// The user finished it.
    public func completed(at now: Date) throws -> TaskItem {
        try requireActive()

        var updated = self
        updated.status = .completed
        return updated
    }

    /// Back into the outstanding pile, from either finished or filed away.
    ///
    /// Rejections are discarded here too: they described a moment that is now behind a
    /// completion, and a task returning to the pile deserves to be judged on its merits.
    public func reopened(at now: Date) throws -> TaskItem {
        guard status != .active else { throw TaskTransitionError.alreadyActive }

        var updated = self
        updated.status = .active
        updated.rejections = []
        return updated
    }

    /// Filed away: kept for the user's records, never recommended again.
    ///
    /// Allowed from outstanding *and* from finished, because archiving is a filing action on
    /// the record rather than a judgement about the work. Only archiving something already
    /// archived is refused, since it would be a change that changes nothing.
    public func archived(at now: Date) throws -> TaskItem {
        guard status != .archived else { throw TaskTransitionError.alreadyArchived }

        var updated = self
        updated.status = .archived
        return updated
    }

    // MARK: - Recommendation feedback

    /// The user said "Not this".
    ///
    /// The task stays outstanding. Turning down a *recommendation* is not refusing the *work*,
    /// and treating it as such would punish the user for telling NEXT something useful —
    /// rejection rate is the engine's most valuable tuning signal (PRODUCT_SPEC.md §14).
    ///
    /// Rejections accumulate oldest first; the penalty is computed from the newest one and
    /// decays, so a task turned down at lunchtime can come back in the evening.
    public func rejected(_ reason: RejectionReason, at now: Date) throws -> TaskItem {
        try requireActive()

        var updated = self
        updated.rejections.append(Rejection(reason: reason, at: now))
        return updated
    }

    // MARK: - Content

    /// Records the concrete first physical step, e.g. "Open the assignment instructions."
    ///
    /// The text is trimmed, and a blank one is refused rather than stored, because
    /// `hasConcreteNextAction` — and therefore the startability factor in ranking — treats
    /// whitespace as absent. Storing `"   "` would let a task advertise a first step it does
    /// not have.
    ///
    /// Requires an outstanding task: the next action is what makes something startable, so it
    /// is meaningless on work that is finished or filed away. Reopen first.
    public func withNextAction(_ action: String, at now: Date) throws -> TaskItem {
        try requireActive()

        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskTransitionError.emptyNextAction }

        var updated = self
        updated.nextAction = trimmed
        return updated
    }

    // MARK: - Guards

    /// Refuses anything that only makes sense on outstanding work.
    private func requireActive() throws {
        guard status == .active else { throw TaskTransitionError.notActive(status) }
    }
}
