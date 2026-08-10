import Foundation
import NextKit
import Observation
import UserNotifications

/// Settings — what NEXT is allowed to do.
///
/// Permission is asked for **here**, at the moment the user switches a reminder on, rather than
/// at launch (PRODUCT_SPEC.md §4.1). Being asked to allow notifications before you have written
/// down a single task is a request with no context, and the honest answer to it is no.
@MainActor
@Observable
final class SettingsViewModel {

    private(set) var preferences: ReminderPreferences
    private(set) var cloudIntelligenceConsented: Bool

    /// What the system says about notification permission.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Set when the user turned reminders on but the system said no.
    private(set) var notice: String?

    /// Read and written directly by the picker; the root applies it.
    let appearance: AppearanceState

    private let store: AppSettingsStore
    private let scheduler: any NotificationScheduling
    private let repository: any TaskRepository
    private let timeSource: any TimeSource
    private let calendar: Calendar

    init(
        store: AppSettingsStore = AppSettingsStore(),
        scheduler: any NotificationScheduling = SystemNotificationScheduler(),
        repository: any TaskRepository,
        appearance: AppearanceState = AppearanceState(),
        timeSource: any TimeSource = SystemTimeSource(),
        calendar: Calendar = .current
    ) {
        self.appearance = appearance
        self.store = store
        self.scheduler = scheduler
        self.repository = repository
        self.timeSource = timeSource
        self.calendar = calendar
        self.preferences = store.reminderPreferences
        self.cloudIntelligenceConsented = store.cloudIntelligenceConsented
    }

    /// True when a reminder switch is on but iOS will not deliver anything.
    ///
    /// Worth surfacing: a switch that says "on" while the system silently drops everything is
    /// the app lying about what it is doing.
    var remindersBlockedBySystem: Bool {
        wantsNotifications && (authorization == .denied)
    }

    private var wantsNotifications: Bool {
        preferences.deadlineRemindersEnabled || preferences.dailyReminderEnabled
    }

    func load() async {
        authorization = await scheduler.authorizationStatus()
    }

    // MARK: Reminder settings

    func setDeadlineReminders(_ enabled: Bool) async {
        preferences.deadlineRemindersEnabled = enabled
        await applyPreferenceChange(turnedSomethingOn: enabled)
    }

    func setDailyReminder(_ enabled: Bool) async {
        preferences.dailyReminderEnabled = enabled
        await applyPreferenceChange(turnedSomethingOn: enabled)
    }

    func setDailyReminderHour(_ hour: Int) async {
        preferences.dailyReminderHour = hour
        await applyPreferenceChange(turnedSomethingOn: false)
    }

    func setLeadTime(_ leadTime: TimeInterval) async {
        preferences.deadlineLeadTime = leadTime
        await applyPreferenceChange(turnedSomethingOn: false)
    }

    private func applyPreferenceChange(turnedSomethingOn: Bool) async {
        store.reminderPreferences = preferences
        notice = nil

        if turnedSomethingOn, authorization == .notDetermined {
            _ = await scheduler.requestAuthorization()
            authorization = await scheduler.authorizationStatus()
        }

        guard wantsNotifications, authorization == .authorized else {
            // Nothing pending while nothing is wanted or allowed. Leaving stale reminders
            // scheduled after the user switched them off would be the app ignoring them.
            await scheduler.cancelAll()
            if turnedSomethingOn, authorization == .denied {
                notice = "Notifications are turned off for NEXT in the Settings app."
            }
            return
        }

        await reschedule()
    }

    /// Recomputes the whole plan and hands it to the system.
    func reschedule() async {
        guard let tasks = try? await repository.fetchAll() else { return }

        let reminders = ReminderPlanner.reminders(
            for: tasks,
            preferences: preferences,
            now: timeSource.now,
            calendar: calendar
        )
        await scheduler.replacePending(with: reminders)
    }

    // MARK: Intelligence consent

    /// Turning this on is the user agreeing that task text may leave the device.
    ///
    /// Nothing reads it yet — the only provider is the offline template one, which sends
    /// nothing anywhere. The switch exists first so a cloud provider cannot be added later
    /// without a consent gate already standing in front of it (`PRIVACY.md`).
    func setCloudIntelligenceConsent(_ consented: Bool) {
        cloudIntelligenceConsented = consented
        store.cloudIntelligenceConsented = consented
    }
}
