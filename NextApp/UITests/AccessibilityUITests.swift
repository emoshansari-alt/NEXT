import XCTest

/// The automated half of the accessibility audit `PRODUCT_SPEC.md` §11 makes release-blocking.
///
/// P8 says an accessibility defect in a core flow is a release blocker, and until now nothing had
/// ever checked. `performAccessibilityAudit()` covers what a machine can genuinely judge:
/// contrast, element descriptions, hit-region size, clipped text under Dynamic Type, and
/// conflicting traits.
///
/// **What it does not cover is written down rather than implied.** VoiceOver gesture traversal and
/// rotor behaviour, real Dynamic Type rendering on device, and haptics all need hardware —
/// `RELEASE_GATED.md` B5. A green run here is not a claim that NEXT is accessible; it is a claim
/// that the automatable checks pass on every core screen, which is a smaller and true statement.
final class AccessibilityUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        if let contentSize {
            // The documented way to drive Dynamic Type from a UI test. Set at launch so the
            // whole app lays out at that size rather than re-flowing mid-run.
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    private func skipOnboarding(_ app: XCUIApplication) {
        let skip = app.buttons["onboarding-skip-button"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        skip.tap()
    }

    private func captureOneTask(_ app: XCUIApplication, text: String = "Finish the history essay") {
        let add = app.buttons["empty-add-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let field = app.textFields["capture-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)

        let save = app.buttons["capture-save-single-button"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: save
        )
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 10), .completed)
        save.tap()

        let done = app.buttons["capture-done-button"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        done.tap()
    }

    /// Audits whatever is currently on screen, naming the screen in any failure.
    private func audit(
        _ app: XCUIApplication,
        _ screen: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try app.performAccessibilityAudit()
        } catch {
            XCTFail("\(screen) failed the accessibility audit: \(error)", file: file, line: line)
        }
    }

    // MARK: Every core screen

    func testOnboardingPassesTheAudit() {
        let app = launch()
        XCTAssertTrue(app.buttons["onboarding-skip-button"].waitForExistence(timeout: 15))

        audit(app, "Onboarding")
    }

    func testEmptyTodayPassesTheAudit() {
        let app = launch()
        skipOnboarding(app)
        XCTAssertTrue(app.buttons["empty-add-button"].waitForExistence(timeout: 10))

        audit(app, "Today, empty")
    }

    func testCapturePassesTheAudit() {
        let app = launch()
        skipOnboarding(app)
        app.buttons["empty-add-button"].tap()
        XCTAssertTrue(app.textFields["capture-text-field"].waitForExistence(timeout: 5))

        audit(app, "Capture")
    }

    func testTodayWithARecommendationPassesTheAudit() {
        // The screen that matters most: it is the one a user sees every time they open NEXT.
        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))

        audit(app, "Today, recommending")
    }

    func testFocusPassesTheAudit() {
        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)
        app.buttons["start-button"].tap()
        XCTAssertTrue(app.buttons["focus-start-button"].waitForExistence(timeout: 5))

        audit(app, "Focus, choosing a length")

        app.buttons["focus-start-button"].tap()
        XCTAssertTrue(app.buttons["focus-done-button"].waitForExistence(timeout: 5))

        audit(app, "Focus, running")
    }

    func testRescuePassesTheAudit() {
        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)
        app.buttons["im-stuck-button"].tap()
        XCTAssertTrue(app.buttons["rescue-path-tooMuch"].waitForExistence(timeout: 5))

        audit(app, "Rescue, choosing a path")

        app.buttons["rescue-path-tooMuch"].tap()
        XCTAssertTrue(app.buttons["rescue-start-button"].waitForExistence(timeout: 5))

        audit(app, "Rescue, showing a step")
    }

    func testEverythingAndTaskDetailPassTheAudit() {
        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)

        app.buttons["everything-button"].tap()
        XCTAssertTrue(app.buttons["everything-close-button"].waitForExistence(timeout: 5))

        audit(app, "Everything")

        app.buttons["task-row"].firstMatch.tap()
        XCTAssertTrue(app.buttons["detail-save-button"].waitForExistence(timeout: 8))

        audit(app, "Task Detail")
    }

    func testSettingsPassesTheAudit() {
        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)

        app.buttons["everything-button"].tap()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 5))
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["settings-close-button"].waitForExistence(timeout: 5))

        audit(app, "Settings")
    }

    func testMinimumWinPassesTheAudit() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-seed-unreachable"]
        app.launch()
        skipOnboarding(app)

        XCTAssertTrue(app.buttons["minimum-win-button"].waitForExistence(timeout: 10))
        app.buttons["minimum-win-button"].tap()
        XCTAssertTrue(app.buttons["minimum-win-close-button"].waitForExistence(timeout: 5))

        audit(app, "Minimum Win")
    }

    // MARK: The largest Dynamic Type

    func testTodaySurvivesTheLargestAccessibilitySize() {
        // §11 requires the largest sizes not to destroy key screens. The audit's text-clipping
        // check is what catches a layout that has silently stopped fitting.
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        skipOnboarding(app)
        captureOneTask(app, text: "Finish the history essay")

        XCTAssertTrue(
            app.buttons["start-button"].waitForExistence(timeout: 15),
            "the primary action must still be reachable at the largest size"
        )

        audit(app, "Today at accessibility XXXL")
    }

    func testFocusSurvivesTheLargestAccessibilitySize() {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        skipOnboarding(app)
        captureOneTask(app, text: "Finish the history essay")

        app.buttons["start-button"].tap()
        XCTAssertTrue(app.buttons["focus-start-button"].waitForExistence(timeout: 10))
        app.buttons["focus-start-button"].tap()
        XCTAssertTrue(
            app.buttons["focus-done-button"].waitForExistence(timeout: 10),
            "Done must still be reachable at the largest size"
        )

        audit(app, "Focus at accessibility XXXL")
    }
}
