import Foundation
import Testing

@testable import NextKit

/// Where tapping a reminder lands.
///
/// The reminders themselves have been scheduled since Session 7 and have carried a task
/// identifier the whole time — but nothing ever read it back, so tapping "Chemistry worksheet is
/// due tomorrow" opened the app and showed whatever Today happened to be recommending. A
/// notification that names a task and then does not open it is worse than one that says nothing.
@Suite("Reminders — where a tap lands")
struct ReminderDestinationTests {

    private func reminder(taskID: TaskID?, kind: ScheduledReminder.Kind) -> ScheduledReminder {
        ScheduledReminder(
            id: "r1",
            taskID: taskID,
            kind: kind,
            fireAt: .testReference,
            title: "Chemistry worksheet",
            body: "Due tomorrow."
        )
    }

    @Test("a reminder about a task opens that task")
    func deadlineReminderOpensItsTask() {
        let deadline = reminder(taskID: TaskID("chem"), kind: .deadline)

        #expect(deadline.deepLink == .task(TaskID("chem")))
    }

    @Test("the daily reminder opens Today, because it is about the day")
    func dailyReminderOpensToday() {
        #expect(reminder(taskID: nil, kind: .dailyNext).deepLink == .today)
    }

    @Test("what a notification carries is enough to find its way back")
    func userInfoRoundTrips() {
        // The round trip is the whole point: the scheduler writes this and the tap handler reads
        // it, and until both used one key they could drift apart silently.
        let deadline = reminder(taskID: TaskID("chem"), kind: .deadline)

        let destination = ScheduledReminder.destination(fromUserInfo: deadline.userInfo)

        #expect(destination == deadline.deepLink)
    }

    @Test("the daily reminder carries nothing and still resolves")
    func dailyUserInfoRoundTrips() {
        let daily = reminder(taskID: nil, kind: .dailyNext)

        #expect(daily.userInfo.isEmpty)
        #expect(ScheduledReminder.destination(fromUserInfo: daily.userInfo) == .today)
    }

    @Test("a payload NEXT does not recognise opens Today rather than nothing")
    func unknownPayloadFallsBackToToday() {
        // The user tapped a notification and expects the app. An empty screen would be a worse
        // answer than the main one, and this is reachable from an older build's payload.
        #expect(ScheduledReminder.destination(fromUserInfo: [:]) == .today)
        #expect(ScheduledReminder.destination(fromUserInfo: ["somethingElse": "x"]) == .today)
        #expect(ScheduledReminder.destination(fromUserInfo: ["taskID": ""]) == .today)
    }

    @Test("every reminder the planner produces knows where it goes")
    func everyPlannedReminderHasADestination() {
        // Swept across a real plan rather than asserted on fixtures, so a new reminder kind
        // cannot be added without deciding where tapping it should land.
        let tasks = [
            makeTask(id: "chem", title: "Chemistry worksheet", deadline: .daysFromReference(2)),
            makeTask(id: "essay", title: "History essay", deadline: .daysFromReference(4))
        ]

        var preferences = ReminderPreferences.default
        preferences.dailyReminderEnabled = true

        let reminders = ReminderPlanner.reminders(
            for: tasks,
            preferences: preferences,
            now: .testReference,
            calendar: .current
        )

        #expect(reminders.isEmpty == false)
        for planned in reminders {
            let destination = ScheduledReminder.destination(fromUserInfo: planned.userInfo)
            #expect(destination == planned.deepLink, "\(planned.id) does not round trip")
        }
    }
}
