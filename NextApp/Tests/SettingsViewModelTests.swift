import Foundation
import Testing
import UserNotifications

@testable import NextApp
import NextKit

private struct FixedTimeSource: TimeSource {
    let now: Date
}

private let reference = Date(timeIntervalSince1970: 1_773_133_200)  // 2026-03-10 09:00 UTC

/// Records what it was asked to do, and answers however the test needs.
private final class SpyScheduler: NotificationScheduling, @unchecked Sendable {

    var status: UNAuthorizationStatus
    var grantsWhenAsked: Bool

    private(set) var timesAsked = 0
    private(set) var scheduled: [ScheduledReminder] = []
    private(set) var cancelCount = 0

    init(status: UNAuthorizationStatus = .notDetermined, grantsWhenAsked: Bool = true) {
        self.status = status
        self.grantsWhenAsked = grantsWhenAsked
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async -> Bool {
        timesAsked += 1
        status = grantsWhenAsked ? .authorized : .denied
        return grantsWhenAsked
    }

    func replacePending(with reminders: [ScheduledReminder]) async {
        scheduled = reminders
    }

    func cancelAll() async {
        cancelCount += 1
        scheduled = []
    }
}

/// A defaults instance nobody else shares, so tests cannot leak into each other or the app.
private func isolatedDefaults(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "next.tests.\(name)")!
    defaults.removePersistentDomain(forName: "next.tests.\(name)")
    return defaults
}

@MainActor
@Suite("SettingsViewModel — notification permission")
struct SettingsPermissionTests {

    private func model(
        _ scheduler: SpyScheduler,
        name: String,
        tasks: [TaskItem] = []
    ) async -> SettingsViewModel {
        let repository = InMemoryTaskRepository()
        for task in tasks { try? await repository.upsert(task) }

        let model = SettingsViewModel(
            store: AppSettingsStore(defaults: isolatedDefaults(name)),
            scheduler: scheduler,
            repository: repository,
            timeSource: FixedTimeSource(now: reference),
            calendar: .current
        )
        await model.load()
        return model
    }

    @Test("permission is asked for when a reminder is switched on, not at launch")
    func permissionIsRequestedContextually() async {
        // Being asked to allow notifications before writing down a single task is a request
        // with no context, and the honest answer to it is no (PRODUCT_SPEC.md §4.1).
        let scheduler = SpyScheduler()
        let model = await model(scheduler, name: "contextual")

        #expect(scheduler.timesAsked == 0, "loading Settings must not prompt")

        await model.setDailyReminder(true)

        #expect(scheduler.timesAsked == 1)
    }

    @Test("permission is not asked for again once answered")
    func permissionIsAskedOnce() async {
        let scheduler = SpyScheduler(status: .denied)
        let model = await model(scheduler, name: "asked-once")

        await model.setDailyReminder(true)

        #expect(scheduler.timesAsked == 0, "a decided status is not re-prompted")
    }

    @Test("a refused permission is stated rather than left as a switch that does nothing")
    func refusedPermissionIsSurfaced() async {
        // A switch reading "on" while iOS silently drops everything is the app lying.
        let scheduler = SpyScheduler(grantsWhenAsked: false)
        let model = await model(scheduler, name: "refused")

        await model.setDeadlineReminders(true)

        #expect(model.remindersBlockedBySystem)
        #expect(model.notice != nil)
    }

    @Test("turning everything off cancels what was pending")
    func turningOffCancels() async {
        // Leaving reminders scheduled after the user switched them off would be the app
        // ignoring them.
        let scheduler = SpyScheduler(status: .authorized)
        let model = await model(
            scheduler,
            name: "cancel",
            tasks: [
                TaskItem(
                    id: TaskID("chem"), title: "Chem", createdAt: reference,
                    deadline: reference.addingTimeInterval(72 * 3600)
                )
            ]
        )

        await model.setDeadlineReminders(false)

        #expect(scheduler.scheduled.isEmpty)
        #expect(scheduler.cancelCount > 0)
    }

    @Test("with permission granted, switching a reminder on schedules it")
    func grantedPermissionSchedules() async {
        let scheduler = SpyScheduler(status: .authorized)
        let model = await model(
            scheduler,
            name: "schedules",
            tasks: [
                TaskItem(
                    id: TaskID("chem"), title: "Chemistry worksheet", createdAt: reference,
                    deadline: reference.addingTimeInterval(72 * 3600)
                )
            ]
        )

        await model.setDeadlineReminders(true)

        #expect(scheduler.scheduled.count == 1)
        #expect(scheduler.scheduled.first?.taskID == TaskID("chem"))
    }
}

@MainActor
@Suite("SettingsViewModel — intelligence consent")
struct SettingsConsentTests {

    private func model(name: String) -> SettingsViewModel {
        SettingsViewModel(
            store: AppSettingsStore(defaults: isolatedDefaults(name)),
            scheduler: SpyScheduler(),
            repository: InMemoryTaskRepository(),
            timeSource: FixedTimeSource(now: reference)
        )
    }

    @Test("cloud processing is off until the user turns it on")
    func consentDefaultsToOff() {
        // PRIVACY.md promises explicit consent before task text leaves the device. A default of
        // true would make that promise false the moment a cloud provider exists.
        #expect(model(name: "consent-default").cloudIntelligenceConsented == false)
    }

    @Test("consent is remembered, and can be withdrawn")
    func consentPersistsAndIsRevocable() {
        let defaults = isolatedDefaults("consent-persist")
        let store = AppSettingsStore(defaults: defaults)

        let first = SettingsViewModel(
            store: store,
            scheduler: SpyScheduler(),
            repository: InMemoryTaskRepository(),
            timeSource: FixedTimeSource(now: reference)
        )
        first.setCloudIntelligenceConsent(true)

        #expect(store.cloudIntelligenceConsented)

        first.setCloudIntelligenceConsent(false)
        #expect(store.cloudIntelligenceConsented == false, "consent must be revocable")
    }
}

@Suite("AppSettingsStore")
struct AppSettingsStoreTests {

    @Test("reminder preferences survive a round trip")
    func preferencesRoundTrip() {
        let store = AppSettingsStore(defaults: isolatedDefaults("round-trip"))

        var preferences = ReminderPreferences.default
        preferences.dailyReminderEnabled = true
        preferences.dailyReminderHour = 19
        preferences.deadlineLeadTime = 3 * 3600
        store.reminderPreferences = preferences

        #expect(store.reminderPreferences == preferences)
    }

    @Test("unreadable preferences fall back to the defaults rather than failing")
    func corruptPreferencesFallBack() {
        // A setting nobody can decode is worth losing. The app is not.
        let defaults = isolatedDefaults("corrupt")
        defaults.set(Data("not json".utf8), forKey: "next.reminderPreferences")

        #expect(AppSettingsStore(defaults: defaults).reminderPreferences == .default)
    }
}
