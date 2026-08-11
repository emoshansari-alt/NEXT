import XCTest

/// What Today does once a deadline has actually gone — D-030.
///
/// The defect this pins was not that the app had no answer. It had two: `START`, and the "I don't
/// have enough time" path inside `I'm stuck`, which plans against a window the user states and
/// never consults the deadline at all. What it lost was the **signpost**. While a deadline is
/// merely unmeetable, Today offers "What can I still do?" — labelled to match the problem. The
/// moment the deadline passed, `MinimumWinPlanner` returned `.noTimeRemaining`, the button
/// disappeared, and the card was left stating a problem with no visible route out of it.
///
/// Driven through the seeded overdue task, which is two days late with a 25-minute estimate — the
/// same fixture the App Store set's sixth frame uses, so what these tests assert is what a shopper
/// sees.
@MainActor
final class PastDeadlineUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchOverdue() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-seed", "overdue"]
        app.launch()

        let skip = app.buttons["onboarding-skip-button"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: skip
        )
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 15), .completed)
        skip.tap()

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 15))
        return app
    }

    func testThePastDeadlineCardSaysSoWithoutClaimingAWindow() {
        let app = launchOverdue()

        // "There is not enough time left to finish this" describes a window too small to finish
        // in. Once the deadline has gone there is no window, and the sentence describes one that
        // does not exist.
        XCTAssertTrue(
            app.staticTexts["This is past its deadline."].waitForExistence(timeout: 8),
            "an overdue card should state the deadline has passed"
        )
        XCTAssertFalse(
            app.staticTexts["There is not enough time left to finish this."].exists,
            "that sentence claims a window this task no longer has"
        )
    }

    func testTheDirectAffordanceSurvivesTheDeadline() {
        // The defect itself. `minimum-win-button` used to be shown only when a ladder existed,
        // and no ladder exists once the deadline has gone.
        let app = launchOverdue()

        XCTAssertTrue(
            app.buttons["minimum-win-button"].waitForExistence(timeout: 8),
            "the way to something smaller must not vanish when the deadline does"
        )
    }

    func testTheAffordanceOpensRescueOnTheTimeBudget() {
        // Routed into the mechanism that already answers this, rather than a second ladder: the
        // user has said what is in the way by tapping it, so Rescue opens on that path and asks
        // the one thing only they know — how long they have.
        let app = launchOverdue()

        let affordance = app.buttons["minimum-win-button"]
        XCTAssertTrue(affordance.waitForExistence(timeout: 8))
        affordance.tap()

        XCTAssertTrue(
            app.buttons["rescue-budget-30"].waitForExistence(timeout: 8),
            "it should land on the time-budget choices"
        )
        XCTAssertFalse(
            app.buttons["rescue-path-tooMuch"].exists,
            "asking which kind of stuck again would be the app not listening"
        )

        for minutes in [5, 15, 30, 60] {
            XCTAssertTrue(
                app.buttons["rescue-budget-\(minutes)"].exists,
                "every window the product spec offers should be here"
            )
        }
    }

    func testAWindowThatFitsProducesAStep() {
        // The whole point of the route: the overdue worksheet is 25 minutes, so half an hour is
        // enough for Rescue to answer with something to do rather than a refusal.
        let app = launchOverdue()

        app.buttons["minimum-win-button"].tap()
        let thirty = app.buttons["rescue-budget-30"]
        XCTAssertTrue(thirty.waitForExistence(timeout: 8))
        thirty.tap()

        XCTAssertTrue(
            app.buttons["rescue-start-button"].waitForExistence(timeout: 8),
            "a window this task fits into should produce something startable"
        )
    }

    func testStartAndImStuckAreUnchangedByAPassedDeadline() {
        let app = launchOverdue()

        // I'm stuck still asks which kind, rather than inheriting the affordance's shortcut.
        app.buttons["im-stuck-button"].tap()
        XCTAssertTrue(
            app.buttons["rescue-path-tooMuch"].waitForExistence(timeout: 8),
            "I'm stuck must still offer all four paths"
        )
        app.buttons["rescue-close-button"].tap()

        // And START still starts the overdue work, which is the other route that was always there.
        let start = app.buttons["start-button"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        XCTAssertTrue(
            app.buttons["focus-start-button"].waitForExistence(timeout: 8),
            "an overdue task must still be startable"
        )
    }
}
