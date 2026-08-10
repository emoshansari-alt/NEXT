import XCTest

/// Dark mode, driven the way a user drives it.
///
/// The unit tests store the choice and map it to a `ColorScheme`; both would pass against a
/// setting that is saved perfectly and never applied to anything. This is the half that cannot
/// be faked: choose Dark in Settings, come back to Today, and measure the pixels.
@MainActor
final class AppearanceUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        forceAppearance(.light)
        super.tearDown()
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

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["everything-button"].tap()
        let settings = app.buttons["settings-button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        XCTAssertTrue(app.buttons["settings-close-button"].waitForExistence(timeout: 8))
    }

    private func brightnessOfTheScreen() -> CGFloat {
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "settle")], timeout: 0.8)
        return meanBrightness(of: XCUIScreen.main.screenshot().image)
    }

    func testChoosingDarkTurnsTheWholeAppDark() {
        // The phone stays light throughout. The whole point of the setting is that someone whose
        // eyes hurt in a bright app should not have to change their phone to read a task.
        forceAppearance(.light)

        let app = launch(["-ui-seed", "essay"])
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 12))

        let lightBrightness = brightnessOfTheScreen()
        XCTAssertGreaterThan(
            lightBrightness, 0.5,
            "Today should start light, since the phone is light and nothing has been chosen"
        )

        openSettings(app)
        let dark = app.buttons["Dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 8), "Settings should offer Dark in one tap")
        dark.tap()

        // Back to Today, where the change has to be visible — not just inside the sheet that
        // set it. `preferredColorScheme` is applied at the scene root precisely so that a choice
        // made three levels down reaches every screen.
        app.buttons["settings-close-button"].tap()
        XCTAssertTrue(app.buttons["everything-close-button"].waitForExistence(timeout: 8))
        app.buttons["everything-close-button"].tap()
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 8))

        let darkBrightness = brightnessOfTheScreen()
        XCTAssertLessThan(
            darkBrightness, 0.35,
            "choosing Dark must darken Today itself, not only the Settings sheet"
        )
    }

    func testTheChoiceSurvivesARelaunch() {
        // A setting that visibly changes the app and then forgets is worse than one that was
        // never offered, so this is written through as the choice is made rather than on
        // dismiss. The store is the real one here — `-ui-testing` swaps the *task* database, not
        // UserDefaults — so this is the same persistence a user gets.
        forceAppearance(.light)

        let app = launch(["-ui-seed", "essay"])
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 12))
        openSettings(app)
        app.buttons["Dark"].tap()
        app.buttons["settings-close-button"].tap()

        app.terminate()
        let relaunched = launch(["-ui-seed", "essay"])
        XCTAssertTrue(relaunched.buttons["start-button"].waitForExistence(timeout: 12))

        XCTAssertLessThan(
            brightnessOfTheScreen(), 0.35,
            "the chosen appearance should still be dark after a relaunch"
        )

        // Put it back, so this test cannot darken every test that runs after it.
        openSettings(relaunched)
        relaunched.buttons["Match my phone"].tap()
        relaunched.buttons["settings-close-button"].tap()
    }
}
