import Foundation

/// What the user has agreed to be interrupted about.
///
/// Every setting here defaults to the quietest reasonable position. Deadline reminders are on
/// because a deadline reminder is the one notification a student unambiguously asked for by
/// writing down a due date; everything else is opt-in.
public struct ReminderPreferences: Hashable, Sendable, Codable {

    /// "Chemistry worksheet is due tomorrow." Tied to a deadline the user themselves set.
    public var deadlineRemindersEnabled: Bool

    /// How far ahead of the deadline to say so.
    ///
    /// A day by default: far enough to still act, close enough to be about this deadline rather
    /// than a distant one.
    public var deadlineLeadTime: TimeInterval

    /// One reminder a day pointing at whatever NEXT would recommend.
    ///
    /// **Off by default, and deliberately.** A daily nudge is the closest this app comes to an
    /// engagement mechanic, so it only exists if the user goes and asks for it.
    public var dailyReminderEnabled: Bool

    /// The hour of the day, 0–23, for the daily reminder.
    public var dailyReminderHour: Int

    public init(
        deadlineRemindersEnabled: Bool,
        deadlineLeadTime: TimeInterval,
        dailyReminderEnabled: Bool,
        dailyReminderHour: Int
    ) {
        self.deadlineRemindersEnabled = deadlineRemindersEnabled
        self.deadlineLeadTime = deadlineLeadTime
        self.dailyReminderEnabled = dailyReminderEnabled
        self.dailyReminderHour = dailyReminderHour
    }

    public static let `default` = ReminderPreferences(
        deadlineRemindersEnabled: true,
        deadlineLeadTime: 24 * 3600,
        dailyReminderEnabled: false,
        dailyReminderHour: 8
    )

    /// The lead-time choices offered in Settings, in hours.
    public static let leadTimeChoices: [TimeInterval] = [3600, 3 * 3600, 12 * 3600, 24 * 3600, 48 * 3600]
}

/// One notification NEXT would like the system to deliver.
///
/// A plain value, not a `UNNotificationRequest`: `NextKit` cannot import `UserNotifications`
/// (DECISIONS.md D-002), and keeping the plan as data is what lets every scheduling rule be
/// tested without a device or a permission prompt.
public struct ScheduledReminder: Hashable, Sendable, Identifiable {

    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        /// A deadline the user set is approaching.
        case deadline

        /// The optional once-a-day pointer at what to do.
        case dailyNext
    }

    /// Stable across re-planning, so rescheduling replaces a pending notification rather than
    /// stacking a duplicate beside it. Re-planning happens on every change, so this matters.
    public let id: String

    /// The task it concerns, or `nil` for the daily reminder, which is about the day.
    public let taskID: TaskID?

    public let kind: Kind
    public let fireAt: Date
    public let title: String
    public let body: String

    public init(
        id: String,
        taskID: TaskID?,
        kind: Kind,
        fireAt: Date,
        title: String,
        body: String
    ) {
        self.id = id
        self.taskID = taskID
        self.kind = kind
        self.fireAt = fireAt
        self.title = title
        self.body = body
    }
}
