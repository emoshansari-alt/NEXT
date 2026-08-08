import Foundation
import Testing

@testable import NextKit

// The Everything screen's sections (PRODUCT_SPEC.md §4.7). Pure date bucketing, so it lives here
// rather than in the view — a calendar boundary is exactly the kind of thing that is easy to get
// wrong and impossible to check by looking at a screenshot.

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func sections(_ tasks: [TaskItem]) -> TaskSections {
    TaskSections(tasks: tasks, now: .testReference, calendar: utc)
}

@Suite("TaskSections — bucketing")
struct TaskSectionBucketingTests {

    // Reference instant is Tuesday 10 March 2026, 09:00 UTC.

    @Test("a deadline earlier today is overdue, not today")
    func earlierTodayIsOverdue() {
        // 08:00 has passed. Calling it "Today" would hide something already late.
        let task = makeTask(id: "t", deadline: .hoursFromReference(-1))

        let result = sections([task])

        #expect(result.overdue.map(\.id) == [TaskID("t")])
        #expect(result.today.isEmpty)
    }

    @Test("a deadline later today is today")
    func laterTodayIsToday() {
        let task = makeTask(id: "t", deadline: .hoursFromReference(8))

        let result = sections([task])

        #expect(result.today.map(\.id) == [TaskID("t")])
    }

    @Test("the last instant of today is still today")
    func endOfDayIsToday() {
        // 23:59:59 UTC on the reference day.
        let task = makeTask(id: "t", deadline: iso("2026-03-10T23:59:59Z"))

        let result = sections([task])

        #expect(result.today.map(\.id) == [TaskID("t")])
        #expect(result.upcoming.isEmpty)
    }

    @Test("the first instant of tomorrow is upcoming")
    func startOfTomorrowIsUpcoming() {
        let task = makeTask(id: "t", deadline: iso("2026-03-11T00:00:00Z"))

        let result = sections([task])

        #expect(result.upcoming.map(\.id) == [TaskID("t")])
        #expect(result.today.isEmpty)
    }

    @Test("yesterday at any hour is overdue")
    func yesterdayIsOverdue() {
        let task = makeTask(id: "t", deadline: iso("2026-03-09T23:59:00Z"))

        let result = sections([task])

        #expect(result.overdue.map(\.id) == [TaskID("t")])
    }

    @Test("a task with no deadline is undated, never today")
    func undatedIsItsOwnSection() {
        let task = makeTask(id: "t", deadline: nil)

        let result = sections([task])

        #expect(result.undated.map(\.id) == [TaskID("t")])
        #expect(result.today.isEmpty)
        #expect(result.upcoming.isEmpty)
    }

    @Test("completed and archived tasks leave the outstanding sections entirely")
    func finishedWorkIsSeparated() {
        let done = makeTask(id: "done", status: .completed, deadline: .hoursFromReference(-5))
        let filed = makeTask(id: "filed", status: .archived, deadline: .hoursFromReference(-5))

        let result = sections([done, filed])

        #expect(result.overdue.isEmpty, "a finished task is not overdue")
        #expect(result.completed.map(\.id) == [TaskID("done")])
        #expect(result.archived.map(\.id) == [TaskID("filed")])
    }

    @Test("archived work is still reachable rather than disappearing")
    func archivedIsNotHidden() {
        // If archiving made a task invisible everywhere, there would be no way to undo it.
        let filed = makeTask(id: "filed", status: .archived)

        #expect(sections([filed]).archived.isEmpty == false)
    }

    @Test("every task lands in exactly one section")
    func sectionsPartitionTheInput() {
        let tasks = [
            makeTask(id: "overdue", deadline: .hoursFromReference(-30)),
            makeTask(id: "today", deadline: .hoursFromReference(5)),
            makeTask(id: "upcoming", deadline: .daysFromReference(4)),
            makeTask(id: "undated"),
            makeTask(id: "done", status: .completed),
            makeTask(id: "filed", status: .archived)
        ]

        let result = sections(tasks)
        let placed = result.overdue + result.today + result.upcoming
            + result.undated + result.completed + result.archived

        #expect(placed.count == tasks.count, "nothing is lost or double-counted")
        #expect(Set(placed.map(\.id)) == Set(tasks.map(\.id)))
    }
}

@Suite("TaskSections — ordering and presentation")
struct TaskSectionOrderingTests {

    @Test("dated sections run soonest first")
    func datedSectionsAreSoonestFirst() {
        let tasks = [
            makeTask(id: "later", deadline: .daysFromReference(6)),
            makeTask(id: "sooner", deadline: .daysFromReference(2)),
            makeTask(id: "middle", deadline: .daysFromReference(4))
        ]

        #expect(
            sections(tasks).upcoming.map(\.id.rawValue) == ["sooner", "middle", "later"]
        )
    }

    @Test("the most overdue thing is at the top")
    func overdueRunsOldestFirst() {
        let tasks = [
            makeTask(id: "recent", deadline: .hoursFromReference(-2)),
            makeTask(id: "ancient", deadline: .daysFromReference(-9))
        ]

        #expect(sections(tasks).overdue.map(\.id.rawValue) == ["ancient", "recent"])
    }

    @Test("undated tasks run oldest first, so the longest-carried is on top")
    func undatedRunsOldestFirst() {
        let tasks = [
            makeTask(id: "new", createdAt: .daysFromReference(-1)),
            makeTask(id: "old", createdAt: .daysFromReference(-20))
        ]

        #expect(sections(tasks).undated.map(\.id.rawValue) == ["old", "new"])
    }

    @Test("completed work runs most recently finished first")
    func completedRunsNewestFirst() {
        // The opposite of everywhere else, and deliberately: a Completed list is a record of
        // what just happened, so the useful end is the recent one.
        let tasks = [
            makeTask(id: "yesterday", status: .completed, completedAt: .daysFromReference(-1)),
            makeTask(id: "just-now", status: .completed, completedAt: .hoursFromReference(-1))
        ]

        #expect(sections(tasks).completed.map(\.id.rawValue) == ["just-now", "yesterday"])
    }

    @Test("ordering is stable regardless of the order tasks arrive in")
    func orderingIsDeterministic() {
        let tasks = [
            makeTask(id: "a", deadline: .daysFromReference(2)),
            makeTask(id: "b", deadline: .daysFromReference(2)),
            makeTask(id: "c", deadline: .daysFromReference(2))
        ]

        let forward = sections(tasks).upcoming.map(\.id.rawValue)
        let backward = sections(tasks.reversed()).upcoming.map(\.id.rawValue)

        #expect(forward == backward)
        #expect(forward == ["a", "b", "c"], "equal deadlines break by identifier")
    }

    @Test("an empty input produces empty sections rather than anything missing")
    func emptyInputIsEmptySections() {
        let result = sections([])

        #expect(result.isEmpty)
        #expect(result.outstandingCount == 0)
    }

    @Test("the outstanding count excludes finished work")
    func outstandingCountCountsOnlyLiveWork() {
        let tasks = [
            makeTask(id: "overdue", deadline: .hoursFromReference(-3)),
            makeTask(id: "today", deadline: .hoursFromReference(3)),
            makeTask(id: "undated"),
            makeTask(id: "done", status: .completed),
            makeTask(id: "filed", status: .archived)
        ]

        #expect(sections(tasks).outstandingCount == 3)
    }
}
