import XCTest

/// Does work survive the app being killed?
///
/// The oldest gap in `TESTING.md`, and the one the rest of the suite structurally could not
/// answer: `-ui-testing` swaps in a fresh in-memory container on every launch, precisely so the
/// golden path cannot consume its own fixtures. Against a store that is recreated on launch,
/// "relaunch and verify" would pass no matter what the persistence layer did.
///
/// So these tests use `-ui-store-name`, which puts a real SwiftData store on disk in a throwaway
/// location of its own, and `-ui-reset-store` on the first launch only. Every later launch is
/// looking for exactly what the previous one left behind.
///
/// The cycle is the one `TESTING.md` requires: create → terminate → relaunch → verify → modify →
/// terminate → relaunch → verify → complete → terminate → relaunch → verify.
final class PersistenceUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Launches against a named on-disk store, optionally wiping it first.
    ///
    /// Onboarding is reset on every UI-testing launch, so it is stepped through each time. That
    /// is not what a real relaunch does, but it is irrelevant to what is being measured here —
    /// the store is a different thing from the first-run flag, and conflating them would make
    /// this test depend on two mechanisms instead of one.
    private func launch(store: String, reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-store-name", store]
        if reset { app.launchArguments.append("-ui-reset-store") }
        app.launch()

        let skip = app.buttons["onboarding-skip-button"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15), "a UI-testing launch shows onboarding")
        skip.tap()

        return app
    }

    private func captureOneTask(_ app: XCUIApplication, text: String) {
        let add = app.buttons["empty-add-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "a reset store should be empty")
        add.tap()

        let field = app.textFields["capture-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)

        let save = app.buttons["capture-save-single-button"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        waitUntilHittable(save)
        save.tap()

        let done = app.buttons["capture-done-button"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        done.tap()
    }

    /// Opens Everything, which is where stored work is listed whatever its status.
    private func openEverything(_ app: XCUIApplication) {
        let everything = app.buttons["everything-button"]
        XCTAssertTrue(everything.waitForExistence(timeout: 10))
        everything.tap()
    }

    /// Asserts a task is listed, having first confirmed Everything is actually open.
    ///
    /// The confirmation is not ceremony. Today sits behind this sheet and shows the recommended
    /// task's title too, so an unscoped search of the whole hierarchy can match the screen
    /// underneath and pass without Everything having opened at all.
    private func assertEverythingContains(
        _ text: String,
        in app: XCUIApplication,
        message: String
    ) {
        XCTAssertTrue(
            app.buttons["everything-close-button"].waitForExistence(timeout: 10),
            "Everything should be open before looking in it"
        )
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 10), message)
    }

    func testWorkSurvivesBeingKilledThroughEveryStateChange() {
        let store = "relaunch-cycle"
        let title = "Email Professor Adeyemi"
        let nextAction = "Ask about the extension first."

        // 1. Create.
        var app = launch(store: store, reset: true)
        captureOneTask(app, text: title)
        assertEverythingContainsAfterOpening(title, in: app, message: "the task should be saved")
        app.terminate()

        // 2. Relaunch and verify it is still there. This is the assertion the in-memory store
        // could never make honestly.
        app = launch(store: store, reset: false)
        assertEverythingContainsAfterOpening(
            title,
            in: app,
            message: "a captured task must survive the app being killed"
        )

        // 3. Modify, still in this launch.
        //
        // The next-action field rather than the title: it starts empty, so this is a plain type
        // with no text to clear first. Selecting and replacing existing text through XCUITest
        // means press-and-hold and a context menu, which is precisely the kind of fragile
        // interaction that makes a suite fail for reasons unrelated to what it is testing.
        openTask(in: app)

        let nextActionField = app.textFields["detail-next-action-field"]
        XCTAssertTrue(nextActionField.waitForExistence(timeout: 5), "the task should open")
        nextActionField.tap()
        nextActionField.typeText(nextAction)
        expectValue(nextAction, in: nextActionField, timeout: 10)

        let save = app.buttons["detail-save-button"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // Saving does *not* dismiss the detail — it is a pushed screen whose way out is the back
        // button, and assuming otherwise is what this test got wrong first time round. So the
        // write is given time, and the app shown to be responsive, by navigating back and landing
        // on Everything before the app is killed.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the pushed detail should have a way back")
        back.tap()
        XCTAssertTrue(
            app.buttons["everything-close-button"].waitForExistence(timeout: 10),
            "going back should land on Everything"
        )
        app.terminate()

        // 4. Relaunch and verify the edit survived, not merely the task it was made on.
        app = launch(store: store, reset: false)
        openEverything(app)
        openTask(in: app)
        expectValue(nextAction, in: app.textFields["detail-next-action-field"], timeout: 10)

        // 5. Complete it, from Today.
        app.terminate()
        app = launch(store: store, reset: false)

        let start = app.buttons["start-button"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "the task should still be recommended")
        start.tap()
        XCTAssertTrue(app.buttons["focus-start-button"].waitForExistence(timeout: 5))
        app.buttons["focus-start-button"].tap()
        let done = app.buttons["focus-done-button"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(done.label, "Done", "this is the whole task, not a reduced step")
        done.tap()

        // Same reasoning: the completion is written and the recommendation recalculated before
        // the empty state can appear, so waiting for it is waiting for the write.
        XCTAssertTrue(
            app.descendants(matching: .any)["empty-state"].waitForExistence(timeout: 10),
            "completing the only task should leave nothing to recommend"
        )
        app.terminate()

        // 6. Relaunch and verify the completion survived — and that it is filed rather than lost.
        app = launch(store: store, reset: false)
        XCTAssertTrue(
            app.descendants(matching: .any)["empty-state"].waitForExistence(timeout: 10),
            "with the only task complete there should be nothing left to recommend"
        )
        openEverything(app)
        assertEverythingContains(
            title,
            in: app,
            message: "a completed task is filed, not deleted — a state with no way back is a trap"
        )
    }

    func testAResetStoreGenuinelyStartsEmpty() {
        // The other half of the arrangement. If `-ui-reset-store` did not work, the test above
        // could pass by finding a task left behind by a previous run — the exact failure mode
        // the in-memory container was introduced to avoid.
        let store = "relaunch-reset"

        var app = launch(store: store, reset: true)
        captureOneTask(app, text: "Chemistry worksheet")
        app.terminate()

        app = launch(store: store, reset: true)

        XCTAssertTrue(
            app.buttons["empty-add-button"].waitForExistence(timeout: 10),
            "a reset store must not carry anything over from the previous run"
        )
    }

    /// Opens Everything and asserts the text is listed.
    private func assertEverythingContainsAfterOpening(
        _ text: String,
        in app: XCUIApplication,
        message: String
    ) {
        openEverything(app)
        assertEverythingContains(text, in: app, message: message)
    }

    /// Taps the task's row, from inside Everything.
    ///
    /// The row itself, not the text inside it. A `staticText` matching the title also exists on
    /// Today behind the sheet, and tapping that does nothing at all — the failure then surfaces
    /// as the detail screen never appearing, several assertions away from the cause.
    private func openTask(in app: XCUIApplication) {
        XCTAssertTrue(
            app.buttons["everything-close-button"].waitForExistence(timeout: 10),
            "Everything should be open"
        )

        let row = app.buttons["task-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the task should be listed")
        XCTAssertTrue(row.isHittable, "the row must be tappable, not merely present")
        row.tap()

        if !app.buttons["detail-save-button"].waitForExistence(timeout: 8) {
            // Ask the app rather than guess across ten-minute CI round trips.
            XCTFail(
                """
                Tapping the task did not open its detail.
                TREE:
                \(app.debugDescription)
                """
            )
        }
    }


    /// Waits until a control is actually tappable, rather than glancing at it once.
    ///
    /// Existing is not the same as being hittable: the capture buttons sit above the keyboard,
    /// and on a loaded runner the layout can settle a moment after the control appears. A tap on
    /// a covered control fails silently and surfaces as an unrelated assertion further down.
    private func waitUntilHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        XCTAssertEqual(result, .completed, "control never became tappable", file: file, line: line)
    }

    /// Waits for a field to actually hold `expected`, then asserts it.
    ///
    /// A polled wait rather than a glance: `typeText` returns before SwiftUI has necessarily
    /// processed every keystroke, and this suite has already lost a run to reading a half-typed
    /// value on a loaded CI machine.
    private func expectValue(
        _ expected: String,
        in element: XCUIElement,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        _ = XCTWaiter().wait(for: [expectation], timeout: timeout)

        XCTAssertEqual(
            element.value as? String,
            expected,
            "the field should hold what was saved",
            file: file,
            line: line
        )
    }
}
