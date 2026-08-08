import Foundation

/// Everything the user has, sorted into the sections the Everything screen shows
/// (PRODUCT_SPEC.md §4.7).
///
/// This is pure date arithmetic against an injected `now` and `Calendar`, which is why it lives
/// here rather than in the view. Calendar boundaries are easy to get subtly wrong — "earlier
/// today" reading as Today instead of Overdue would quietly hide something already late — and
/// impossible to check by looking at a screenshot.
///
/// What this is deliberately *not*: a board, a filter engine, a tag system, or a second
/// recommendation. Everything is a place to see and fix what NEXT already knows. The decision
/// about what to do next belongs to `RankingEngine` and is made on one screen only.
public struct TaskSections: Hashable, Sendable {

    /// Deadline already passed. Most overdue first — the thing that has been waiting longest is
    /// the one worth seeing.
    public let overdue: [TaskItem]

    /// Due before the end of today. Soonest first.
    public let today: [TaskItem]

    /// Due on a later day. Soonest first.
    public let upcoming: [TaskItem]

    /// No deadline. Oldest first, so what has been carried longest surfaces.
    public let undated: [TaskItem]

    /// Finished. Most recently completed first — a record of what just happened, so the recent
    /// end is the useful one. This is the only section that runs newest first.
    public let completed: [TaskItem]

    /// Filed away. Present so that archiving is reversible; a state with no way back would be a
    /// trap rather than a filing action.
    public let archived: [TaskItem]

    /// How much is actually outstanding. Excludes completed and archived work.
    public var outstandingCount: Int {
        overdue.count + today.count + upcoming.count + undated.count
    }

    public var isEmpty: Bool {
        overdue.isEmpty && today.isEmpty && upcoming.isEmpty
            && undated.isEmpty && completed.isEmpty && archived.isEmpty
    }

    /// Buckets a task list.
    ///
    /// `now` and `calendar` are parameters because `NextKit` never reads either
    /// (DECISIONS.md D-007) — and because "today" is a question only a calendar in a specific
    /// time zone can answer.
    public init(tasks: [TaskItem], now: Date, calendar: Calendar) {
        let startOfTomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        )

        var overdue: [TaskItem] = []
        var today: [TaskItem] = []
        var upcoming: [TaskItem] = []
        var undated: [TaskItem] = []
        var completed: [TaskItem] = []
        var archived: [TaskItem] = []

        for task in tasks {
            switch task.status {
            case .completed:
                completed.append(task)
                continue
            case .archived:
                archived.append(task)
                continue
            case .active:
                break
            }

            guard let deadline = task.deadline else {
                undated.append(task)
                continue
            }

            if deadline < now {
                // Note this is against `now`, not the start of the day: something due at 08:00
                // is late by 09:00, and filing it under Today would hide that.
                overdue.append(task)
            } else if let startOfTomorrow, deadline < startOfTomorrow {
                today.append(task)
            } else {
                upcoming.append(task)
            }
        }

        self.overdue = Self.byDeadline(overdue)
        self.today = Self.byDeadline(today)
        self.upcoming = Self.byDeadline(upcoming)
        self.undated = Self.byCreation(undated)
        self.completed = Self.byCompletionNewestFirst(completed)
        self.archived = Self.byCreation(archived)
    }

    // MARK: Ordering
    //
    // Every comparator falls back to the identifier. Tasks captured from one brain dump share a
    // creation instant exactly and often a deadline too, so without it the order within a group
    // would be left to the sort's discretion and could differ between two launches.

    private static func byDeadline(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { left, right in
            switch (left.deadline, right.deadline) {
            case let (l?, r?) where l != r: l < r
            case (nil, .some): false
            case (.some, nil): true
            default: left.id.rawValue < right.id.rawValue
            }
        }
    }

    private static func byCreation(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { left, right in
            left.createdAt == right.createdAt
                ? left.id.rawValue < right.id.rawValue
                : left.createdAt < right.createdAt
        }
    }

    private static func byCompletionNewestFirst(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { left, right in
            // A completed task with no recorded instant sorts last rather than jumping to the
            // top: unknown is not the same as recent.
            switch (left.completedAt, right.completedAt) {
            case let (l?, r?) where l != r: l > r
            case (nil, .some): false
            case (.some, nil): true
            default: left.id.rawValue < right.id.rawValue
            }
        }
    }
}
