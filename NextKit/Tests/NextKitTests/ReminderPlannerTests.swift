import Foundation
import Testing

@testable import NextKit

// What NEXT would ask iOS to deliver, worked out as a pure function so it can be tested here
// rather than by staring at a device. PRODUCT_SPEC.md §4.14: sparse and useful. No engagement
// bait, no "we miss you", nothing that fires because the user has been away.

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func plan(
    _ tasks: [TaskItem],
    preferences: ReminderPreferences = .default
) -> [ScheduledReminder] {
    ReminderPlanner.reminders(
        for: tasks,
        preferences: preferences,
        now: .testReference,
        calendar: utc
    )
}

@Suite("ReminderPlanner — deadline reminders")
struct DeadlineReminderTests {

    // Reference instant is Tuesday 10 March 2026, 09:00 UTC. Default lead time is 24 hours.

    @Test("a dated task earns one reminder, ahead of the deadline")
    func datedTaskGetsAReminder() throws {
        let task = makeTask(id: "chem", title: "Chemistry worksheet", deadline: .daysFromReference(3))

        let reminders = plan([task])

        #expect(reminders.count == 1)
        let reminder = try #require(reminders.first)
        #expect(reminder.taskID == task.id)
        #expect(reminder.kind == .deadline)
        #expect(reminder.fireAt == Date.daysFromReference(2), "one day before, by default")
    }

    @Test("an undated task earns nothing")
    func undatedTaskGetsNothing() {
        #expect(plan([makeTask(id: "someday")]).isEmpty)
    }

    @Test("finished and filed work is never reminded about")
    func finishedWorkIsSilent() {
        // A notification about something already done is the clearest possible signal that an
        // app is not paying attention.
        let tasks = [
            makeTask(id: "done", status: .completed, deadline: .daysFromReference(3)),
            makeTask(id: "filed", status: .archived, deadline: .daysFromReference(3))
        ]

        #expect(plan(tasks).isEmpty)
    }

    @Test("a reminder whose moment has passed is not scheduled")
    func pastRemindersAreDropped() {
        // Due in twelve hours, with a lead time of a day: the reminder would have fired
        // yesterday. iOS would deliver it immediately, which is a notification about nothing.
        let task = makeTask(id: "chem", deadline: .hoursFromReference(12))

        #expect(plan([task]).isEmpty)
    }

    @Test("an overdue task is not nagged about")
    func overdueTasksAreNotNagged() {
        // The user knows. Daily replanning surfaces it in the app; a push notification about it
        // would be the app telling them off (P5).
        let task = makeTask(id: "late", deadline: .daysFromReference(-2))

        #expect(plan([task]).isEmpty)
    }

    @Test("deadline reminders can be turned off entirely")
    func deadlineRemindersRespectThePreference() {
        var preferences = ReminderPreferences.default
        preferences.deadlineRemindersEnabled = false

        let task = makeTask(id: "chem", deadline: .daysFromReference(3))

        #expect(plan([task], preferences: preferences).isEmpty)
    }

    @Test("the lead time is configurable")
    func leadTimeIsConfigurable() throws {
        var preferences = ReminderPreferences.default
        preferences.deadlineLeadTime = 2 * 24 * 3600

        let task = makeTask(id: "chem", deadline: .daysFromReference(5))
        let reminder = try #require(plan([task], preferences: preferences).first)

        #expect(reminder.fireAt == Date.daysFromReference(3))
    }

    @Test("reminders come back soonest first")
    func remindersAreOrdered() {
        let tasks = [
            makeTask(id: "later", deadline: .daysFromReference(9)),
            makeTask(id: "sooner", deadline: .daysFromReference(3)),
            makeTask(id: "middle", deadline: .daysFromReference(6))
        ]

        #expect(plan(tasks).map(\.taskID?.rawValue) == ["sooner", "middle", "later"])
    }
}

@Suite("ReminderPlanner — the daily reminder")
struct DailyReminderTests {

    private var enabled: ReminderPreferences {
        var preferences = ReminderPreferences.default
        preferences.dailyReminderEnabled = true
        preferences.dailyReminderHour = 8
        return preferences
    }

    @Test("the daily reminder is off unless the user turns it on")
    func dailyReminderIsOptIn() {
        #expect(plan([makeTask(id: "chem")]).contains { $0.kind == .dailyNext } == false)
    }

    @Test("when on, it fires at the chosen hour on the next day it can")
    func dailyReminderFiresAtTheChosenHour() throws {
        // 08:00 today has already passed at 09:00, so the next one is tomorrow.
        let reminders = plan([makeTask(id: "chem")], preferences: enabled)
        let daily = try #require(reminders.first { $0.kind == .dailyNext })

        #expect(daily.fireAt == iso("2026-03-11T08:00:00Z"))
        #expect(daily.taskID == nil, "it is about the day, not one task")
    }

    @Test("an hour still to come today fires today")
    func laterTodayFiresToday() throws {
        var preferences = enabled
        preferences.dailyReminderHour = 18

        let daily = try #require(
            plan([makeTask(id: "chem")], preferences: preferences).first { $0.kind == .dailyNext }
        )

        #expect(daily.fireAt == iso("2026-03-10T18:00:00Z"))
    }

    @Test("with nothing outstanding, there is nothing to remind about")
    func noDailyReminderWithNoWork() {
        // A daily nudge with an empty task list is the engagement bait the spec forbids.
        let finished = makeTask(id: "done", status: .completed)

        #expect(plan([finished], preferences: enabled).isEmpty)
    }
}

@Suite("ReminderPlanner — limits and tone")
struct ReminderLimitTests {

    @Test("no more reminders are planned than iOS will hold")
    func respectsTheSystemLimit() {
        // iOS keeps 64 pending local notifications per app and silently drops the rest. Sending
        // more would mean the ones that get dropped are chosen by the system, not by us — and
        // the ones that matter most are the soonest.
        let many = (0..<200).map {
            makeTask(id: "t\($0)", deadline: .daysFromReference(Double(2 + $0)))
        }

        let reminders = plan(many)

        #expect(reminders.count == ReminderPlanner.systemLimit)
        #expect(reminders.first?.taskID == TaskID("t0"), "the soonest survive the cap")
    }

    @Test("identifiers are stable, so rescheduling replaces rather than duplicates")
    func identifiersAreStable() {
        // Re-planning happens on every change. Unstable identifiers would stack duplicates.
        let task = makeTask(id: "chem", deadline: .daysFromReference(3))

        #expect(plan([task]).map(\.id) == plan([task]).map(\.id))
    }

    @Test("a deadline reminder says what is due and when, and nothing else")
    func deadlineCopyIsFactual() throws {
        let task = makeTask(id: "chem", title: "Chemistry worksheet", deadline: .daysFromReference(3))
        let reminder = try #require(plan([task]).first)

        #expect(reminder.title == "Chemistry worksheet")
        #expect(reminder.body == "Due tomorrow.")
    }

    @Test("no reminder pressures, guilts, or begs")
    func copyIsNeverManipulative() {
        // "We miss you!" is the named counter-example in the spec. So is anything implying the
        // user has let something slip.
        let banned = [
            "miss you", "don't forget", "still", "again", "behind", "failed",
            "streak", "hurry", "!", "come back", "haven't"
        ]

        var preferences = ReminderPreferences.default
        preferences.dailyReminderEnabled = true
        let tasks = (0..<5).map {
            makeTask(id: "t\($0)", title: "Task \($0)", deadline: .daysFromReference(Double(3 + $0)))
        }

        for reminder in plan(tasks, preferences: preferences) {
            let text = (reminder.title + " " + reminder.body).lowercased()
            for word in banned {
                #expect(!text.contains(word), "'\(word)' in: \(reminder.title) / \(reminder.body)")
            }
        }
    }
}
