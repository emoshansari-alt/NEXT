import Foundation

/// Works out what NEXT would ask the system to deliver.
///
/// A pure function so every rule below is testable at Tier 1 rather than by watching a device
/// and waiting. The app takes this list and turns it into `UNNotificationRequest`s; it makes no
/// decisions of its own about what should fire or when.
///
/// The governing rule is PRODUCT_SPEC.md §4.14: **sparse and useful**. Nothing here fires
/// because the user has been away, nothing accumulates, and nothing is sent to bring anyone
/// back. Every notification traces to a deadline the user typed, or to a daily reminder they
/// went into Settings and switched on.
public enum ReminderPlanner {

    /// iOS keeps at most 64 pending local notifications per app and silently discards the rest.
    ///
    /// Planning more would not mean more reminders — it would mean the system choosing which to
    /// drop, arbitrarily. Capping here means *we* choose, and the soonest are what survive.
    public static let systemLimit = 64

    public static func reminders(
        for tasks: [TaskItem],
        preferences: ReminderPreferences,
        now: Date,
        calendar: Calendar
    ) -> [ScheduledReminder] {
        var planned = deadlineReminders(
            for: tasks, preferences: preferences, now: now, calendar: calendar
        )

        if let daily = dailyReminder(
            for: tasks, preferences: preferences, now: now, calendar: calendar
        ) {
            planned.append(daily)
        }

        return Array(planned.sorted { earlier($0, $1) }.prefix(systemLimit))
    }

    // MARK: Deadlines

    private static func deadlineReminders(
        for tasks: [TaskItem],
        preferences: ReminderPreferences,
        now: Date,
        calendar: Calendar
    ) -> [ScheduledReminder] {
        guard preferences.deadlineRemindersEnabled else { return [] }

        return tasks.compactMap { task in
            // Something already finished or filed away is not worth interrupting anyone about.
            // A notification about a completed task is the clearest possible signal that an app
            // is not paying attention.
            guard task.status.isRecommendable, let deadline = task.deadline else { return nil }

            let fireAt = deadline.addingTimeInterval(-preferences.deadlineLeadTime)

            // A moment already past would be delivered by iOS immediately — a notification
            // about nothing. An overdue task is deliberately silent too: the user knows, daily
            // replanning surfaces it in the app, and a push about it would be the app telling
            // them off (P5).
            guard fireAt > now, deadline > now else { return nil }

            return ScheduledReminder(
                id: "deadline.\(task.id.rawValue)",
                taskID: task.id,
                kind: .deadline,
                fireAt: fireAt,
                title: task.title,
                body: duePhrase(deadline: deadline, from: fireAt, calendar: calendar)
            )
        }
    }

    /// "Due tomorrow." — said relative to when the notification actually arrives, not to now.
    /// A reminder that reads "due in 3 days" when it lands the day before would be wrong.
    private static func duePhrase(
        deadline: Date,
        from fireAt: Date,
        calendar: Calendar
    ) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: fireAt),
            to: calendar.startOfDay(for: deadline)
        ).day ?? 0

        switch days {
        case ..<1: return "Due today."
        case 1: return "Due tomorrow."
        default: return "Due in \(days) days."
        }
    }

    // MARK: The daily reminder

    private static func dailyReminder(
        for tasks: [TaskItem],
        preferences: ReminderPreferences,
        now: Date,
        calendar: Calendar
    ) -> ScheduledReminder? {
        guard preferences.dailyReminderEnabled else { return nil }

        // With nothing outstanding there is nothing to point at, and a daily nudge over an
        // empty list is exactly the engagement bait the spec rules out.
        let outstanding = tasks.filter(\.status.isRecommendable)
        guard !outstanding.isEmpty else { return nil }

        guard let fireAt = nextOccurrence(
            ofHour: preferences.dailyReminderHour, after: now, calendar: calendar
        ) else { return nil }

        return ScheduledReminder(
            id: "daily",
            taskID: nil,
            kind: .dailyNext,
            fireAt: fireAt,
            title: "NEXT",
            // States what is there. Does not tell the user to do it.
            body: outstanding.count == 1
                ? "One thing outstanding."
                : "\(outstanding.count) things outstanding."
        )
    }

    private static func nextOccurrence(
        ofHour hour: Int,
        after now: Date,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = 0
        components.second = 0

        guard let today = calendar.date(from: components) else { return nil }
        guard today <= now else { return today }

        return calendar.date(byAdding: .day, value: 1, to: today)
    }

    // MARK: Ordering

    /// Soonest first, with a total order so the cap always drops the same ones.
    private static func earlier(_ lhs: ScheduledReminder, _ rhs: ScheduledReminder) -> Bool {
        lhs.fireAt == rhs.fireAt ? lhs.id < rhs.id : lhs.fireAt < rhs.fireAt
    }
}
