import Foundation
import Testing

@testable import NextApp
import NextKit

/// Tapping a reminder should open the task it was about.
///
/// Reminders have carried a task identifier since Session 7 and nothing ever read it back, so
/// "Chemistry worksheet is due tomorrow" opened the app and showed whatever Today happened to be
/// recommending. A notification that names a task and then does not open it is worse than one
/// that says nothing at all.
///
/// What is *not* covered here, and is stated rather than implied: no notification has ever been
/// delivered. Delivery is `RELEASE_GATED.md` B5 and needs a device. These tests cover the payload
/// and the routing — everything between "iOS handed us a tap" and "the task is on screen".
@Suite("Notification routing")
struct NotificationRoutingTests {

    @Test("a reminder's payload resolves to its own task")
    func payloadResolvesToTheTask() {
        let reminder = ScheduledReminder(
            id: "deadline-chem",
            taskID: TaskID("chem"),
            kind: .deadline,
            fireAt: Date(),
            title: "Chemistry worksheet",
            body: "Due tomorrow."
        )

        let destination = NotificationRouter.destination(fromNotificationPayload: reminder.userInfo)

        #expect(destination == .task(TaskID("chem")))
    }

    @Test("the daily reminder opens Today")
    func dailyPayloadResolvesToToday() {
        let daily = ScheduledReminder(
            id: "daily",
            taskID: nil,
            kind: .dailyNext,
            fireAt: Date(),
            title: "NEXT",
            body: "One thing outstanding."
        )

        #expect(NotificationRouter.destination(fromNotificationPayload: daily.userInfo) == .today)
    }

    @Test("a payload NEXT does not recognise still opens the app rather than nothing")
    func unknownPayloadsAreHarmless() {
        // Reachable from an older build's notification still sitting in Notification Centre, and
        // from anything else that can put a payload in front of the app. None of it may be
        // interpreted, and none of it may fail.
        let cases: [[AnyHashable: Any]] = [
            [:],
            ["somethingElse": "x"],
            [ScheduledReminder.taskIDUserInfoKey: ""],
            [ScheduledReminder.taskIDUserInfoKey: 42],
            [ScheduledReminder.taskIDUserInfoKey: ["nested": "value"]]
        ]

        for payload in cases {
            #expect(
                NotificationRouter.destination(fromNotificationPayload: payload) == .today,
                "\(payload) should fall back to Today"
            )
        }
    }
}

@MainActor
@Suite("DeepLinkInbox")
struct DeepLinkInboxTests {

    @Test("a tap waits until something is ready to act on it")
    func aTapIsHeldUntilTaken() {
        // A notification can arrive before Today exists — a cold launch from the lock screen is
        // exactly that — so the destination has to survive the gap.
        let inbox = DeepLinkInbox()

        inbox.receive(.task(TaskID("chem")))

        #expect(inbox.pending == .task(TaskID("chem")))
    }

    @Test("taking a tap consumes it, so it cannot be acted on twice")
    func takingClearsIt() {
        // SwiftUI rebuilds a view whenever it likes. A link that stayed pending would reopen the
        // same task every time Today's body ran, and the user could never navigate away.
        let inbox = DeepLinkInbox()
        inbox.receive(.task(TaskID("chem")))

        #expect(inbox.take() == .task(TaskID("chem")))
        #expect(inbox.pending == nil)
        #expect(inbox.take() == nil)
    }

    @Test("a later tap replaces an unread one")
    func theLatestTapWins() {
        // Two notifications tapped in quick succession: the second is what the user is asking for.
        let inbox = DeepLinkInbox()

        inbox.receive(.task(TaskID("chem")))
        inbox.receive(.task(TaskID("essay")))

        #expect(inbox.take() == .task(TaskID("essay")))
    }
}
