import Foundation
import NextKit
import Observation
import UserNotifications

/// Somewhere a tap can be left until a screen is ready to act on it.
///
/// A notification can arrive before Today exists — a cold launch from the lock screen is exactly
/// that — so the destination is parked here rather than delivered to a view that may not be
/// listening yet. Today observes it and clears it once acted on.
@MainActor
@Observable
final class DeepLinkInbox {

    private(set) var pending: DeepLink?

    func receive(_ link: DeepLink) {
        pending = link
    }

    func take() -> DeepLink? {
        defer { pending = nil }
        return pending
    }
}

/// Turns a tapped notification into somewhere to go.
///
/// The whole of the decision — which link, and what an unrecognised payload means — lives in
/// `ScheduledReminder` in `NextKit`, where it is tested without a device or a permission prompt.
/// This is the adapter: it reads what iOS hands over and passes it on.
///
/// Reminders have carried a task identifier since Session 7 and nothing ever read it back, so
/// tapping "Chemistry worksheet is due tomorrow" opened the app and showed whatever Today happened
/// to be recommending. A notification that names a task and then does not open it is worse than
/// one that says nothing.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {

    private let inbox: DeepLinkInbox

    init(inbox: DeepLinkInbox) {
        self.inbox = inbox
        super.init()
    }

    /// Registers as the delegate. Must happen before the app finishes launching, or a tap that
    /// started the app is delivered to nobody.
    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let destination = Self.destination(
            fromNotificationPayload: response.notification.request.content.userInfo
        )
        await inbox.receive(destination)
    }

    /// Reads what iOS handed over.
    ///
    /// Separated from the delegate method so it can be tested: fabricating a
    /// `UNNotificationResponse` is not something an app can honestly do, and a payload reader that
    /// is only exercised by a real delivered notification is a payload reader with no tests at all.
    ///
    /// Only the one key is read, and only as a string. Everything else in the payload is ignored
    /// rather than interpreted — a notification is data arriving from outside the app's control,
    /// and the decision of what it means belongs to `ScheduledReminder`, not to whatever the
    /// dictionary happens to contain.
    static func destination(fromNotificationPayload payload: [AnyHashable: Any]) -> DeepLink {
        var carried: [String: String] = [:]
        if let value = payload[ScheduledReminder.taskIDUserInfoKey] as? String {
            carried[ScheduledReminder.taskIDUserInfoKey] = value
        }
        return ScheduledReminder.destination(fromUserInfo: carried)
    }

    /// What to do when a reminder fires while NEXT is already open.
    ///
    /// Nothing. The user is looking at the app; a banner telling them about a task they can
    /// already see is the interruption this product exists to remove, and Today has by then
    /// recalculated anyway.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}
