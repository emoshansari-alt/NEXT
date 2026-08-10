import XCTest

/// Captures the six App Store frames from the running app.
///
/// The whole point of this file is that the store listing shows NEXT rendering, not a
/// reproduction of NEXT. Every earlier mockup was CSS built from `NextPalette` and `NextType`;
/// accurate about colour and metrics and still a drawing. These are the app.
///
/// **Kept out of the ordinary run by `-skip-testing`, not by a flag inside the test.** Two
/// attempts to gate this on an environment variable both skipped silently — `env:` on the step
/// sets it on the runner machine, and `TEST_RUNNER_CAPTURE_SCREENSHOTS` did not reach
/// `ProcessInfo` either. Whether that is an Xcode 26 change or a misuse on my part stopped
/// mattering after the second round: the destination is something CI states explicitly, so the
/// scheduling decision belongs in the workflow where it is visible, not in a runtime read that
/// can fail to nothing. The main test step skips this class; the capture step runs only it.
///
/// Frames, in the order the listing tells them (D-024):
///
/// 1. Capture, mid-dump          4. Focus, running
/// 2. Today, recommending        5. Rescue, four ways of being stuck
/// 3. Why this one               6. Today on overdue work
///
/// Frame 3 used to be the "Why this?" alert. That control is retired — it was a modal repeating
/// the card — so the beat is unchanged and the screen is not: it is the card carrying its own
/// explanation, on a task with no deadline, which is the state where that line is the only place
/// the reason appears.
///
/// Only the *data* is seeded — see `NEXTApp.seedArgument`. Nothing about the interface is staged.
// Main-actor isolated for the same reason `AccessibilityUITests` is: the appearance and
// screenshot APIs it uses are main-actor bound.
@MainActor
final class ScreenshotCaptureUITests: XCTestCase {

    /// The portrait sizes the App Store accepts for the largest iPhones: 6.9-inch, which Apple
    /// now wants as the primary, and 6.7-inch. Which one comes out depends on which Pro Max the
    /// runner image happens to carry, so the size is recorded rather than demanded.
    private let acceptedSizes = [
        CGSize(width: 1320, height: 2868),
        CGSize(width: 1290, height: 2796)
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    // MARK: Capturing

    /// Saves the screen under a name the compositing step can find.
    ///
    /// `.keepAlways`, because the default lifetime deletes attachments for passing tests — and
    /// every one of these passes, so the default would throw away the entire deliverable.
    @discardableResult
    private func capture(_ app: XCUIApplication, _ name: String) -> UIImage {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // Recorded rather than asserted. A runner whose only iPhone is the wrong size should
        // still hand back usable frames plus a loud note about what they actually are, instead
        // of failing and producing nothing.
        let size = shot.image.size
        let scale = shot.image.scale
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        let label = acceptedSizes.contains(pixels) ? "store size" : "NOT a store size"
        XCTContext.runActivity(
            named: "\(name): \(Int(pixels.width))x\(Int(pixels.height)) — \(label)"
        ) { _ in }

        return shot.image
    }

    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extraArguments
        app.launch()

        let skip = app.buttons["onboarding-skip-button"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: skip
        )
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 15), .completed)
        skip.tap()
        return app
    }

    /// Waits for the screen to settle before the shutter. Without it the card's one animated
    /// moment is caught mid-transition, which is exactly the frame nobody wants.
    private func settle() {
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "settle")], timeout: 0.9)
    }

    /// Dismisses the keyboard's own first-run card, which is Apple's and not NEXT's.
    ///
    /// A fresh simulator shows QuickPath — "Speed up your typing by sliding your finger across the
    /// letters" with a Continue button — the first time a keyboard appears, and it covers the
    /// keyboard entirely. It was in the composited set: the **first frame of the listing** was an
    /// iOS tutorial with NEXT visible above it, which is both a bad advertisement and a picture of
    /// something other than the product.
    ///
    /// Silent when it is absent, because whether a given runner image has shown it before is not
    /// something to make the capture depend on.
    private func dismissKeyboardTutorial(_ app: XCUIApplication) {
        let continueButton = app.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 3) {
            continueButton.tap()
            settle()
        }
    }

    // MARK: The six frames

    func testCaptureTheAppStoreSet() throws {
        // 1 — Capture, mid-dump.
        var app = launch()
        app.buttons["empty-add-button"].tap()
        let field = app.textFields["capture-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        dismissKeyboardTutorial(app)
        field.typeText("Chem test monday, finish history slides friday, email professor about the extension, reading for seminar")
        settle()
        capture(app, "01-capture")

        // 2 — Today, recommending. Seeded so the card carries a deadline and an estimate; typing
        // the same task through Capture would leave both empty and show less of the product.
        app = launch(["-ui-seed", "essay"])
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 12))
        settle()
        capture(app, "02-today")

        // 3 — The card explaining itself. Same beat as before and a different screen: "Why this?"
        // is retired, so the explanation is on the card. Seeded without a deadline, because that
        // is the state where the reason line is the only place it appears — the case the old
        // alert was the sole route to.
        //
        // Asserted before the shutter. A frame whose whole subject is the explanation must not be
        // captured without one, and a missing reason line would otherwise produce a frame that
        // looks like frame 2 and says nothing.
        app = launch(["-ui-seed", "reason"])
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 12))
        XCTAssertTrue(
            app.staticTexts["recommendation-reason"].waitForExistence(timeout: 6),
            "frame 3 is the card explaining itself — without the reason there is nothing to show"
        )
        settle()
        capture(app, "03-why")

        // 4 — Focus, running. Relaunched on the essay, which is the task frames 2 and 5 are about.
        app = launch(["-ui-seed", "essay"])
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 12))
        app.buttons["start-button"].tap()
        let justStart = app.buttons["focus-start-button"]
        XCTAssertTrue(justStart.waitForExistence(timeout: 8))
        app.buttons["focus-timer-25"].tap()
        XCTAssertTrue(app.buttons["focus-done-button"].waitForExistence(timeout: 8))
        settle()
        capture(app, "04-focus")

        // 5 — Rescue.
        app.buttons["focus-im-stuck-button"].tap()
        XCTAssertTrue(app.buttons["rescue-path-tooMuch"].waitForExistence(timeout: 8))
        settle()
        capture(app, "05-stuck")

        // 6 — Overdue. Still captured in **light**, and now by choice rather than by constraint:
        // Dark mode ships and `AppearanceUITests` measures it, so the listing may claim it. Which
        // appearance this frame shows is a D-024 decision about the set, made with the owner, and
        // changing it here would be taking that decision on the way past. Add `-ui-appearance
        // dark` when it is taken.
        app = launch(["-ui-seed", "overdue"])
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 12))
        settle()
        capture(app, "06-late")
    }
}
