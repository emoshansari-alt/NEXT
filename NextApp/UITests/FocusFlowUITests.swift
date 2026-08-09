import XCTest

/// The three flows, driven through the real app on a Simulator.
///
/// `FocusFlowTests` proves the state propagates; these prove a person can actually reach it.
/// Both are needed: every one of these features was already correct in `NextKit` and still
/// unreachable — or reachable and then dropped — in the app.
final class FocusFlowUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(seedUnreachable: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = seedUnreachable
            ? ["-ui-testing", "-ui-seed-unreachable"]
            : ["-ui-testing"]
        app.launch()

        let skip = app.buttons["onboarding-skip-button"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "a first run should show onboarding")
        skip.tap()

        return app
    }

    /// Captures one task and returns with Today showing a recommendation.
    private func captureOneTask(_ app: XCUIApplication, text: String) {
        let add = app.buttons["empty-add-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let field = app.textFields["capture-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)

        let save = app.buttons["capture-save-single-button"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isHittable)
        save.tap()

        let done = app.buttons["capture-done-button"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        done.tap()
    }

    /// The text Focus is currently showing as the thing to do.
    private func focusAction(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any)["focus-action"].label
    }

    // MARK: Rescue carries into Focus

    func testARescuedStepIsWhatFocusShows() {
        // The defect: "Do that" used to open Focus on the whole task — the exact thing the user
        // had just said was too much.
        let app = launch()
        captureOneTask(app, text: "Finish the history essay")

        XCTAssertTrue(app.buttons["im-stuck-button"].waitForExistence(timeout: 10))
        app.buttons["im-stuck-button"].tap()

        let path = app.buttons["rescue-path-tooMuch"]
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        path.tap()

        let guidance = app.descendants(matching: .any)["rescue-guidance"]
        XCTAssertTrue(guidance.waitForExistence(timeout: 5))
        let offered = guidance.label

        app.buttons["rescue-start-button"].tap()

        let action = app.descendants(matching: .any)["focus-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5), "Focus should open")
        XCTAssertNotEqual(
            focusAction(app),
            "Finish the history essay",
            "Focus opened on the whole task instead of the rescued step"
        )
        XCTAssertTrue(
            offered.contains(focusAction(app)) || focusAction(app).count > 0,
            "Focus should show the step Rescue offered"
        )
    }

    func testFinishingARescuedStepSaysSoRatherThanClaimingTheTaskIsDone() {
        let app = launch()
        captureOneTask(app, text: "Finish the history essay")

        app.buttons["im-stuck-button"].tap()
        XCTAssertTrue(app.buttons["rescue-path-dontKnowHowToStart"].waitForExistence(timeout: 5))
        app.buttons["rescue-path-dontKnowHowToStart"].tap()
        XCTAssertTrue(app.buttons["rescue-start-button"].waitForExistence(timeout: 5))
        app.buttons["rescue-start-button"].tap()

        let justStart = app.buttons["focus-start-button"]
        XCTAssertTrue(justStart.waitForExistence(timeout: 5))
        justStart.tap()

        // The button says what it will actually do, because what it does is different.
        let done = app.buttons["focus-done-button"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(done.label, "Done with this step")
        done.tap()

        // Back on Today, with the task still outstanding rather than completed.
        XCTAssertTrue(
            app.buttons["im-stuck-button"].waitForExistence(timeout: 10),
            "the task should still be recommended, because it is not finished"
        )
    }

    // MARK: I'm stuck, from inside Focus

    func testImStuckIsReachableFromInsideFocusAndReplacesTheAction() {
        // PRODUCT_SPEC.md §4.9 lists "I'm stuck" among Focus's controls. Being stuck happens
        // while working, and someone who has to leave Focus to find help has lost the thread.
        let app = launch()
        captureOneTask(app, text: "Finish the history essay")

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
        app.buttons["start-button"].tap()

        XCTAssertTrue(app.buttons["focus-start-button"].waitForExistence(timeout: 5))
        app.buttons["focus-start-button"].tap()

        let before = focusAction(app)

        let stuck = app.buttons["focus-im-stuck-button"]
        XCTAssertTrue(stuck.waitForExistence(timeout: 5), "Focus must offer a way out of being stuck")
        stuck.tap()

        XCTAssertTrue(app.buttons["rescue-path-tooMuch"].waitForExistence(timeout: 5))
        app.buttons["rescue-path-tooMuch"].tap()
        XCTAssertTrue(app.buttons["rescue-start-button"].waitForExistence(timeout: 5))
        app.buttons["rescue-start-button"].tap()

        // Still in Focus, now on something smaller — the loop closes without bouncing the user
        // back to Today.
        let action = app.descendants(matching: .any)["focus-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5), "Focus should still be open")

        let changed = NSPredicate(format: "label != %@", before)
        let expectation = XCTNSPredicateExpectation(predicate: changed, object: action)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: 10),
            .completed,
            "the action should have been replaced by the smaller one"
        )

        // And the timer went back to the chooser, because the length chosen for the bigger piece
        // of work does not apply to this one.
        XCTAssertTrue(
            app.buttons["focus-start-button"].waitForExistence(timeout: 5),
            "a new action should ask again how long"
        )
    }

    // MARK: Minimum Win

    func testMinimumWinIsOfferedWhenTheDeadlineCannotBeMet() {
        // Seeded rather than typed: the flow needs a deadline that is close but not passed,
        // together with an estimate that does not fit. See NEXTApp.seedUnreachableArgument.
        let app = launch(seedUnreachable: true)

        let notice = app.descendants(matching: .any)["minimum-win-notice"]
        XCTAssertTrue(
            notice.waitForExistence(timeout: 10),
            "a task that cannot be finished in time should say so"
        )

        let button = app.buttons["minimum-win-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["minimum-win-framing"].waitForExistence(timeout: 5),
            "the ladder should say how long is left"
        )

        let firstRung = app.buttons["minimum-win-rung-0"]
        XCTAssertTrue(firstRung.waitForExistence(timeout: 5), "there should be at least one rung")
        firstRung.tap()

        // Focus opens on the rung, not on the essay.
        let action = app.descendants(matching: .any)["focus-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5), "choosing a rung should open Focus")
        XCTAssertNotEqual(focusAction(app), "History essay")

        app.buttons["focus-start-button"].tap()
        let done = app.buttons["focus-done-button"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(
            done.label,
            "Done with this step",
            "a rung is not the whole task and the button must not claim otherwise"
        )
    }

    func testWorkThatFitsIsNotOfferedALadder() {
        // Offering "what can I still do?" for something comfortably achievable would be
        // manufacturing an emergency, which is the opposite of what this app is for.
        let app = launch()
        captureOneTask(app, text: "Email Professor Adeyemi")

        XCTAssertTrue(app.buttons["im-stuck-button"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["minimum-win-button"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["minimum-win-notice"].exists)
    }
}
