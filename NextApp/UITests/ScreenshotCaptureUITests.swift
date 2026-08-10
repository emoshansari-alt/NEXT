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
/// 3. Why this?                  6. Today on overdue work, dark appearance
///
/// Only the *data* is seeded — see `NEXTApp.seedArgument`. Nothing about the interface is staged.
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

    override func tearDown() {
        XCUIDevice.shared.appearance = .light
        super.tearDown()
    }

    // MARK: Capturing

    /// Saves the screen under a name the compositing step can find.
    ///
    /// `.keepAlways`, because the default lifetime deletes attachments for passing tests — and
    /// every one of these passes, so the default would throw away the entire deliverable.
    private func capture(_ app: XCUIApplication, _ name: String) {
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

    // MARK: The six frames

    func testCaptureTheAppStoreSet() throws {
        // 1 — Capture, mid-dump.
        var app = launch()
        app.buttons["empty-add-button"].tap()
        let field = app.textFields["capture-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("Chem test monday, finish history slides friday, email professor about the extension, reading for seminar")
        settle()
        capture(app, "01-capture")

        // 2 — Today, recommending. Seeded so the card carries a deadline and an estimate; typing
        // the same task through Capture would leave both empty and show less of the product.
        app = launch(["-ui-seed", "essay"])
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 12))
        settle()
        capture(app, "02-today")

        // 3 — Why this? The real explanation, generated by the engine rather than written here.
        app.buttons["why-this-button"].tap()
        XCTAssertTrue(app.staticTexts["Why this?"].waitForExistence(timeout: 6))
        settle()
        capture(app, "03-why")

        // 4 — Focus, running.
        app.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 6))
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

        // 6 — Overdue, in the dark appearance. The one frame of the six that is dark, and the
        // reason `testTheCardScreensPassTheAuditInDarkMode` exists: the listing may not claim an
        // appearance the audit has never seen.
        XCUIDevice.shared.appearance = .dark
        app = launch(["-ui-seed", "overdue"])
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 12))
        settle()
        capture(app, "06-late")
    }
}
