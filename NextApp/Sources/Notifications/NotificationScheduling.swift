import Foundation
import NextKit
import UserNotifications

/// Delivering the plan `ReminderPlanner` produces.
///
/// A protocol so view models can be tested without a permission prompt, a notification centre,
/// or a device. Nothing here decides *what* to schedule — that is settled in `NextKit`, where it
/// is testable — this only carries the answer to iOS.
protocol NotificationScheduling: Sendable {

    /// Whether the user has already been asked, and what they said.
    func authorizationStatus() async -> UNAuthorizationStatus

    /// Asks for permission. Returns whether it was granted.
    func requestAuthorization() async -> Bool

    /// Replaces every pending NEXT reminder with this set.
    func replacePending(with reminders: [ScheduledReminder]) async

    /// Cancels everything, for when the user turns reminders off.
    func cancelAll() async
}

/// The real one.
struct SystemNotificationScheduler: NotificationScheduling {

    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        // Sound and badge are not requested. A deadline reminder is information, and a badge
        // that sits there counting outstanding work is exactly the low-grade pressure the
        // product is meant to remove.
        (try? await center.requestAuthorization(options: [.alert])) ?? false
    }

    func replacePending(with reminders: [ScheduledReminder]) async {
        // Wholesale replacement rather than diffing. Reminder identifiers are stable, so the
        // set is a complete statement of what should be pending — and re-planning happens on
        // every change, which makes "remove everything, add the current answer" both simpler
        // and impossible to leave in a half-updated state.
        await cancelAll()

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.userInfo = reminder.taskID.map { ["taskID": $0.rawValue] } ?? [:]

            let interval = reminder.fireAt.timeIntervalSinceNow
            guard interval > 0 else { continue }

            let request = UNNotificationRequest(
                identifier: reminder.id,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
    }
}
