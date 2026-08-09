import SwiftUI

/// How a failure message reaches someone who cannot see it appear.
///
/// Every error surface in NEXT is a line of text that fades into place — the ephemeral-store
/// banner, a capture that could not be saved, a refused notification permission, a purchase that
/// did not go through. Sighted users get those for free: the layout moves and the eye follows.
/// With VoiceOver, nothing happens at all. Worse, most of these sit *before* the control the user
/// just operated in traversal order — the Settings notice is above the toggle, the capture failure
/// is below the button — so even sweeping the screen again may not reach it, and the user is left
/// believing an action succeeded when it did not.
///
/// `PRODUCT_SPEC.md` §11 makes an accessibility defect in a core flow release-blocking, and an
/// unannounced failure is one: the whole content of the message is that something the user asked
/// for did not happen.
///
/// ## Why the decision is separated from the announcing
///
/// XCUITest cannot assert that VoiceOver spoke. So the part that can be got wrong — *when* to
/// speak — is a pure function over the old and new message, unit-tested at Tier 2, and the part
/// that cannot be tested is one line with no logic in it. That split is what makes the claim
/// "errors are announced" evidenced rather than asserted.
enum ErrorAnnouncement {

    /// What should be spoken when a message surface changes, or `nil` for silence.
    ///
    /// Three rules, and each exists because the opposite is a real annoyance rather than a
    /// theoretical one:
    ///
    /// - A message appearing is announced. That is the whole point.
    /// - A message being *cleared* is not. Silence is what the absence of a problem sounds like,
    ///   and announcing "" would interrupt whatever the user was reading to say nothing.
    /// - An unchanged message is not re-announced. A view body can run many times for reasons
    ///   that have nothing to do with the error, and a failure that repeats itself every time
    ///   SwiftUI re-evaluates is worse than one that is never spoken.
    static func spoken(replacing old: String?, with new: String?) -> String? {
        guard let new, !new.isEmpty, new != old else { return nil }
        return new
    }
}

/// Where an announcement actually goes. Substitutable so a test can watch it without VoiceOver.
struct AnnouncementRelay: Sendable {

    var speak: @Sendable (String) -> Void

    /// The real one: hands the string to VoiceOver, which speaks it when it next can.
    static let system = AnnouncementRelay { message in
        AccessibilityNotification.Announcement(message).post()
    }
}

private struct AnnouncesFailure: ViewModifier {

    let message: String?
    let relay: AnnouncementRelay

    func body(content: Content) -> some View {
        content.onChange(of: message) { previous, current in
            if let spoken = ErrorAnnouncement.spoken(replacing: previous, with: current) {
                relay.speak(spoken)
            }
        }
    }
}

extension View {

    /// Speaks this screen's failure message whenever one appears.
    ///
    /// **Applied to the container, not to the message itself.** Every one of these surfaces is
    /// inside an `if let`, so the `Text` does not exist until the failure does — watching it for
    /// a change would mean watching a view that is created already in its final state, and the
    /// nil-to-message transition, the only one worth announcing, would never be seen.
    ///
    /// The message's own `accessibilityIdentifier` stays on the `Text` where it belongs. A
    /// container's identifier overwrites its children's, and this suite has already lost several
    /// CI rounds to exactly that (`TESTING.md`).
    func announcesFailure(
        _ message: String?,
        relay: AnnouncementRelay = .system
    ) -> some View {
        modifier(AnnouncesFailure(message: message, relay: relay))
    }
}
