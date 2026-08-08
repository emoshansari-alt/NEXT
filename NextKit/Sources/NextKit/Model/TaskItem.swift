import Foundation

/// One thing the user has to do.
///
/// Named `TaskItem`, not `Task`, to avoid colliding with Swift Concurrency's `Task`.
///
/// This is a value type with no persistence framework attached. The SwiftData `@Model` class
/// lives in `NextApp` and maps to and from this type at the repository boundary
/// (DECISIONS.md D-006), which keeps the whole domain layer testable off-device.
public struct TaskItem: Hashable, Sendable, Identifiable {

    // MARK: Identity

    public let id: TaskID

    /// What the user called it. e.g. "History essay".
    public var title: String

    /// When the task entered the system. Supplied by the caller — `NextKit` never reads
    /// the clock itself (DECISIONS.md D-007).
    public let createdAt: Date

    /// When the task last changed. One of the fields PRODUCT_SPEC.md §7 says a task carries.
    ///
    /// Every transition writes the instant it was handed, which is the point: `completed(at:)`
    /// and its neighbours read at the call site as though they record something, and now they
    /// do. Without it the storage layer would have to invent a timestamp of its own, which
    /// would put a hidden clock read back underneath the domain (DECISIONS.md D-007).
    ///
    /// Equal to `createdAt` for a task nothing has happened to yet.
    public var updatedAt: Date

    // MARK: State

    public var status: TaskStatus

    /// When the user finished it, or `nil` if they have not.
    ///
    /// Kept alongside `status` rather than derived from it because the instant itself is the
    /// product data: the Everything screen's Completed section (PRODUCT_SPEC.md §4.7) orders by
    /// it, and daily replanning (§4.13) needs to know *which day* work was finished, not merely
    /// that it was. Reopening clears it, because a task back in the pile has no completion.
    public var completedAt: Date?

    // MARK: Ranking inputs

    /// When it is due. `nil` means genuinely undated, not "unknown" — an undated task is a
    /// legitimate thing a student has, and it simply contributes no urgency.
    public var deadline: Date?

    /// How much it matters. Two levels only — see `Importance`.
    public var importance: Importance

    /// Roughly how long it will take. `nil` means not estimated, which is the common case
    /// straight out of a brain dump. An unestimated task is never hidden by a time budget:
    /// unknown duration means "might fit", not "does not fit".
    public var estimatedMinutes: Int?

    /// The concrete first physical step, e.g. "Open the assignment instructions."
    /// Its presence is what makes a task startable — there is nothing left to decide.
    public var nextAction: String?

    /// Tasks that must be finished before this one can begin. While any is outstanding this
    /// task is blocked and will not be recommended.
    public var prerequisiteIDs: [TaskID]

    /// The larger task this one is a step of, if any.
    public var parentID: TaskID?

    /// Every time the user said "Not this", oldest first. This is a permanent record.
    ///
    /// Nothing removes entries from it. Rejection *rate* is the single most valuable signal for
    /// tuning the ranking engine (PRODUCT_SPEC.md §14), so deleting the evidence to suppress a
    /// penalty would trade product data for something `rejectionsSupersededAt` handles without
    /// losing anything.
    public var rejections: [Rejection]

    /// The instant after which earlier rejections no longer count *against* the task.
    ///
    /// Set when the user starts the task or reopens it: at that moment they have chosen the
    /// work themselves, so an earlier "Not this" has plainly been overtaken and must stop
    /// suppressing the very thing they are doing. `nil` means nothing has superseded anything.
    ///
    /// A watermark rather than a deletion. The rejection still happened and is still counted
    /// wherever rate matters; it simply stops being held against the task at ranking time.
    public var rejectionsSupersededAt: Date?

    public init(
        id: TaskID,
        title: String,
        createdAt: Date,
        updatedAt: Date? = nil,
        status: TaskStatus = .active,
        completedAt: Date? = nil,
        deadline: Date? = nil,
        importance: Importance = .normal,
        estimatedMinutes: Int? = nil,
        nextAction: String? = nil,
        prerequisiteIDs: [TaskID] = [],
        parentID: TaskID? = nil,
        rejections: [Rejection] = [],
        rejectionsSupersededAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        // A task nothing has happened to yet was last changed when it was created. Defaulting
        // to `createdAt` rather than to some sentinel keeps `updatedAt` non-optional, so no
        // caller has to decide what a missing edit time means.
        self.updatedAt = updatedAt ?? createdAt
        self.status = status
        self.completedAt = completedAt
        self.deadline = deadline
        self.importance = importance
        self.estimatedMinutes = estimatedMinutes
        self.nextAction = nextAction
        self.prerequisiteIDs = prerequisiteIDs
        self.parentID = parentID
        self.rejections = rejections
        self.rejectionsSupersededAt = rejectionsSupersededAt
    }

    // MARK: Derived

    /// Whether the deadline has already passed at the given instant.
    /// Takes `now` as a parameter because `NextKit` never reads the clock (D-007).
    public func isOverdue(at now: Date) -> Bool {
        guard let deadline else { return false }
        return deadline < now
    }

    /// The most recent rejection, if the user has ever turned this task down.
    ///
    /// The whole history, watermark or not — this is the record, and it is what a rejection-rate
    /// measurement reads. Ranking uses `activeRejections` instead.
    public var latestRejection: Rejection? {
        rejections.max { $0.at < $1.at }
    }

    /// The rejections that still count against this task, oldest first.
    ///
    /// Anything from before `rejectionsSupersededAt` is excluded: the user has since started or
    /// reopened the task, which overrides their earlier "Not this" far more directly than a
    /// decay curve does. Everything at or after the watermark is a fresh opinion and still
    /// counts. Nothing is removed from `rejections` to achieve this.
    public var activeRejections: [Rejection] {
        guard let watermark = rejectionsSupersededAt else { return rejections }
        return rejections.filter { $0.at >= watermark }
    }

    /// The most recent rejection that has not been superseded, which is the one the ranking
    /// penalty decays from.
    public var latestActiveRejection: Rejection? {
        activeRejections.max { $0.at < $1.at }
    }

    /// Whether a real first step is recorded. Whitespace does not count — an empty next
    /// action would make the task look startable while leaving the user with nothing to do.
    public var hasConcreteNextAction: Bool {
        guard let nextAction else { return false }
        return !nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether this task fits inside a stated time budget.
    /// An unestimated task always fits — see `estimatedMinutes`.
    public func fits(withinMinutes budget: Int?) -> Bool {
        guard let budget, let estimatedMinutes else { return true }
        return estimatedMinutes <= budget
    }
}
