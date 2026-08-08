import XCTest

/// Tier 2 UI tests, run on the iOS Simulator.
///
/// The golden path from TESTING.md, as far as the app currently goes:
/// fresh install → empty state → capture → extraction → confirmation → recommendation → START →
/// Focus → Done → next recommendation.
///
/// Still missing from it, and deliberately named here so the gap stays visible: onboarding, and
/// relaunch-persistence (the UI target gets a fresh in-memory store per launch, so a relaunch
/// test would need a different arrangement).
final class GoldenPathUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Every run starts from a clean in-memory store. Without this the suite would share the
        // simulator's real database, and the golden-path test — which completes a task — would
        // slowly consume its own fixtures. A test whose result depends on how many times it has
        // run before is not a test.
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }

    /// Captures one task by the manual route and returns with Today showing a recommendation.
    @discardableResult
    private func captureOneTask(_ app: XCUIApplication, text: String) -> XCUIApplication {
        let add = app.buttons["empty-add-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "a first run must offer a way to add")
        add.tap()

        let field = app.textFields["capture-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)

        // Assert the text actually landed before acting on it. Without this, a field that
        // silently ignores input leaves the save button disabled, the tap does nothing, and the
        // failure surfaces several assertions later pointing at the wrong thing.
        XCTAssertEqual(field.value as? String, text, "the field should hold what was typed")

        let saveSingle = app.buttons["capture-save-single-button"]
        XCTAssertTrue(saveSingle.waitForExistence(timeout: 5))
        XCTAssertTrue(saveSingle.isEnabled, "save should be enabled once there is text")
        // Reachable with the keyboard up. Existing is not the same as being tappable, and a tap
        // on a covered control fails silently several assertions before anyone notices.
        XCTAssertTrue(saveSingle.isHittable, "save must be reachable while the keyboard is up")
        saveSingle.tap()

        let done = app.buttons["capture-done-button"]
        if !done.waitForExistence(timeout: 8) {
            // Dump what is actually on screen. Guessing at an invisible failure across CI
            // round-trips is slower than asking the app once.
            XCTFail(
                """
                Saving did not reach the confirmation screen.
                store-warning present: \(app.descendants(matching: .any)["store-warning"].exists)
                capture-failure present: \(app.descendants(matching: .any)["capture-failure"].exists)
                capture-failure label: \(app.descendants(matching: .any)["capture-failure"].label)
                TREE:
                \(app.debugDescription)
                """
            )
            return app
        }
        done.tap()

        return app
    }

    func testFirstRunIsEmptyAndOffersAWayOut() {
        // NEXT must not invent tasks the student never wrote. An empty first run is correct —
        // an empty first run with no way forward is a dead end.
        let app = launch()

        XCTAssertTrue(app.descendants(matching: .any)["empty-state"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["empty-add-button"].exists)
        XCTAssertFalse(app.buttons["start-button"].exists, "nothing should be recommended yet")
    }

    func testManualCaptureProducesSomethingToStart() {
        let app = launch()

        captureOneTask(app, text: "Email Professor Adeyemi")

        XCTAssertTrue(
            app.buttons["start-button"].waitForExistence(timeout: 10),
            "a captured task should immediately become something to start"
        )
    }

    func testBrainDumpGoesThroughConfirmationBeforeAnythingIsSaved() {
        let app = launch()

        app.buttons["empty-add-button"].tap()

        let field = app.textFields["capture-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("chem test monday, email professor, finish history slides friday")

        app.buttons["capture-extract-button"].tap()

        // Confirmation is not optional. Nothing has been written at this point.
        XCTAssertTrue(
            app.descendants(matching: .any)["capture-confirmation"].waitForExistence(timeout: 10),
            "extraction must land on confirmation, not save straight away"
        )

        let accept = app.buttons["confirmation-accept-button"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        accept.tap()

        let done = app.buttons["capture-done-button"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
    }

    func testStartOpensFocusAndDoneReturnsWithANewRecommendation() {
        let app = launch()
        captureOneTask(app, text: "Email Professor Adeyemi")

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
        app.buttons["start-button"].tap()

        // Wait on the Done button rather than the action text. The action is a combined
        // accessibility element, and which XCUIElementType a combined element surfaces as is
        // not contractual — Done is a real button whose presence proves Focus opened.
        let done = app.buttons["focus-done-button"]
        XCTAssertTrue(
            done.waitForExistence(timeout: 5),
            "START should open Focus on the recommended action"
        )
        XCTAssertTrue(app.descendants(matching: .any)["focus-action"].exists)

        done.tap()

        // That was the only task, so completion should land on the explained empty state rather
        // than a blank screen.
        XCTAssertTrue(
            app.descendants(matching: .any)["empty-state"].waitForExistence(timeout: 5),
            "completing the last task should say so, not show nothing"
        )
    }

    func testStoppingFocusReturnsWithoutCompleting() {
        let app = launch()
        captureOneTask(app, text: "Email Professor Adeyemi")

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
        app.buttons["start-button"].tap()

        let stop = app.buttons["focus-stop-button"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()

        XCTAssertTrue(
            app.buttons["start-button"].waitForExistence(timeout: 5),
            "stopping must not complete the task"
        )
    }

    func testWhyThisAlwaysHasAnAnswer() {
        // The recommendation is never an unknowable oracle — PRODUCT_SPEC.md §4.4.
        let app = launch()
        captureOneTask(app, text: "Email Professor Adeyemi")

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
        captureOneTask(app, text: "Email Professor Adeyemi")

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
        for identifier in ["not-this-button", "why-this-button", "add-button"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists, "\(identifier) should be present")
            XCTAssertTrue(button.isHittable, "\(identifier) should be reachable by tap")
        }
    }
}
