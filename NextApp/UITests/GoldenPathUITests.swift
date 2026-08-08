import XCTest

/// Tier 2 UI tests, run on the iOS Simulator.
///
/// This is the beginning of the golden path from TESTING.md. It currently covers the part of
/// the loop that exists — recommendation, START, Focus, Done, next recommendation. Onboarding,
/// brain dump, extraction, confirmation and relaunch-persistence join it as those surfaces are
/// built; the test is deliberately named for the whole path so its gaps stay visible.
final class GoldenPathUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    func testAppLaunchesShowingSomethingToStart() {
        let app = launch()

        let start = app.buttons["start-button"]
        XCTAssertTrue(
            start.waitForExistence(timeout: 10),
            "Today should offer something to start on launch"
        )
        XCTAssertTrue(start.isHittable)
    }

    func testStartOpensFocusAndDoneReturnsWithANewRecommendation() {
        let app = launch()

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
        app.buttons["start-button"].tap()

        let focusAction = app.otherElements["focus-action"]
        XCTAssertTrue(
            focusAction.waitForExistence(timeout: 5),
            "START should open Focus on the recommended action"
        )

        let done = app.buttons["focus-done-button"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        // Completion flows straight back into the loop: something new is offered.
        XCTAssertTrue(
            app.buttons["start-button"].waitForExistence(timeout: 5),
            "Completing a task should immediately produce the next recommendation"
        )
    }

    func testStoppingFocusReturnsWithoutCompleting() {
        let app = launch()

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
        app.buttons["start-button"].tap()

        let stop = app.buttons["focus-stop-button"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 5))
    }

    func testWhyThisAlwaysHasAnAnswer() {
        // The recommendation is never an unknowable oracle — PRODUCT_SPEC.md §4.4.
        let app = launch()

        let why = app.buttons["why-this-button"]
        XCTAssertTrue(why.waitForExistence(timeout: 10))
        why.tap()

        XCTAssertTrue(
            app.alerts.firstMatch.waitForExistence(timeout: 5),
            "Why this? must always produce an explanation"
        )
    }

    func testEverySecondaryActionIsReachable() {
        let app = launch()

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
        for identifier in ["not-this-button", "why-this-button"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists, "\(identifier) should be present")
            XCTAssertTrue(button.isHittable, "\(identifier) should be reachable by tap")
        }
    }
}
