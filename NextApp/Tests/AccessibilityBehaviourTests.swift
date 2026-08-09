import Foundation
import SwiftUI
import Testing

@testable import NextApp

/// Tier 2. The two accessibility behaviours that a UI test structurally cannot observe.
///
/// `performAccessibilityAudit()` inspects a rendered screen, which is the right tool for labels,
/// contrast and hit regions and the wrong one for these. XCUITest cannot hear VoiceOver speak,
/// and there is no audit category for motion. Both would therefore have been claims with no
/// evidence behind them — so the decision in each case is factored out as a value the tests can
/// hold, and only the untestable one-liner is left in the view.
///
/// This is the same split `NextPaletteTests` uses for contrast: assert the *values*, and let the
/// audit assert what is drawn from them.

@Suite("Errors are announced, not merely rendered")
struct ErrorAnnouncementTests {

    @Test("a failure appearing is announced")
    func anAppearingFailureIsSpoken() {
        #expect(
            ErrorAnnouncement.spoken(replacing: nil, with: "Could not save that.")
                == "Could not save that."
        )
    }

    @Test("a failure being cleared is not announced")
    func clearingIsSilent() {
        // Silence is what "the problem is gone" sounds like. Announcing the clearance would
        // interrupt whatever the user had moved on to, to tell them nothing.
        #expect(ErrorAnnouncement.spoken(replacing: "Could not save that.", with: nil) == nil)
    }

    @Test("the same failure is never announced twice")
    func repeatsAreSilent() {
        // A view body runs whenever SwiftUI decides it should, for reasons that have nothing to
        // do with the error. A failure that re-announces itself on every evaluation is worse
        // than one that is never spoken — it makes the screen unusable rather than uninformative.
        #expect(
            ErrorAnnouncement.spoken(
                replacing: "Could not save that.", with: "Could not save that."
            ) == nil
        )
    }

    @Test("a failure replaced by a different failure is announced")
    func aChangedFailureIsSpoken() {
        // The second failure is new information: the first thing the user tried did not work,
        // and neither did the next.
        #expect(
            ErrorAnnouncement.spoken(replacing: "Could not save that.", with: "Still no.")
                == "Still no."
        )
    }

    @Test("an empty message is not announced")
    func emptyIsSilent() {
        #expect(ErrorAnnouncement.spoken(replacing: nil, with: "") == nil)
    }

    @Test("the relay passes the message through untouched")
    func theRelayCarriesTheMessage() {
        // The one line that cannot be tested is the one that hands the string to VoiceOver. What
        // can be tested is that nothing between the decision and that line edits, truncates or
        // reorders what the user is told.
        let spoken = RecordedAnnouncements()
        let relay = AnnouncementRelay { spoken.append($0) }

        relay.speak("Saving is unavailable. Anything you do now will not be kept.")

        #expect(spoken.all == ["Saving is unavailable. Anything you do now will not be kept."])
    }
}

@Suite("Reduce Motion is honoured, not approximated")
struct ReduceMotionTests {

    @Test("the card change uses the still curve when motion is reduced")
    func cardChangeIsReducedWhenAsked() {
        #expect(NextMotion.cardChange(reduceMotion: true) == NextMotion.reduced)
    }

    @Test("the card change keeps its spring when motion is not reduced")
    func cardChangeKeepsItsSpringOtherwise() {
        // Both directions, because a function that returned the reduced curve unconditionally
        // would pass the test above and remove the app's one animated moment.
        #expect(NextMotion.cardChange(reduceMotion: false) == NextMotion.cardChange)
    }

    @Test("the reduced curve is a different animation from the full one")
    func theTwoCurvesAreNotTheSame() {
        // Guards the pair above against becoming vacuous: if `reduced` were ever set equal to
        // `cardChange`, both would pass while Reduce Motion did nothing at all.
        #expect(NextMotion.reduced != NextMotion.cardChange)
    }
}

/// Somewhere `Sendable` for a test to collect announcements into.
///
/// `AnnouncementRelay.speak` is `@Sendable`, so the closure cannot capture a plain `var`.
private final class RecordedAnnouncements: @unchecked Sendable {

    private let lock = NSLock()
    private var messages: [String] = []

    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        messages.append(message)
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}
