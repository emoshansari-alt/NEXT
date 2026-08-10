import XCTest

/// Dark mode, driven the way a user drives it.
///
/// The unit tests store the choice and map it to a `ColorScheme`; both would pass against a
/// setting that is saved perfectly and applied to nothing. This is the half that cannot be
/// faked: flip the switch in Settings, come back to Today, and measure the pixels.
@MainActor
final class AppearanceUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Each test states the appearance it starts from, because the preference lives in the real
    /// `UserDefaults` — `-ui-testing` swaps the *task* database, not the settings — so a test
    /// that left dark on would otherwise darken whatever ran next.
    private func launch(startingIn appearance: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-seed", "essay"]
        if let appearance {
            app.launchArguments += ["-ui-appearance", appearance]
        }
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

    private func closeSettingsAndEverything(_ app: XCUIApplication) {
        app.buttons["settings-close-button"].tap()
        XCTAssertTrue(app.buttons["everything-close-button"].waitForExistence(timeout: 8))
        app.buttons["everything-close-button"].tap()
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 8))
    }

    private func brightnessOfTheScreen() -> CGFloat {
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "settle")], timeout: 0.8)
        return meanBrightness(of: XCUIScreen.main.screenshot().image)
    }

    private func setDarkMode(_ on: Bool, in app: XCUIApplication) {
        let toggle = app.switches["settings-dark-mode-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "Settings should offer Dark mode")
        // Reading the value first, so flipping to a state it is already in is a no-op rather
        // than a silent reversal.
        let isOn = (toggle.value as? String) == "1"
        if isOn != on { toggle.tap() }
    }

    func testTurningOnDarkModeDarkensTheWholeApp() {
        let app = launch(startingIn: "light")
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 12))

        XCTAssertGreaterThan(
            brightnessOfTheScreen(), 0.5,
            "Today should start light, because light is the default"
        )

        openSettings(app)
        setDarkMode(true, in: app)

        // Back on Today, where the change has to be visible — not only inside the sheet that set
        // it. `preferredColorScheme` is applied at the scene root precisely so a choice made
        // three levels down reaches every screen.
        closeSettingsAndEverything(app)

        XCTAssertLessThan(
            brightnessOfTheScreen(), 0.35,
            "turning on Dark mode must darken Today itself, not only the Settings sheet"
        )
    }

    func testDarkModeSurvivesARelaunch() {
        // A setting that visibly changes the app and then forgets is worse than one never
        // offered, which is why the choice is written through as it is made rather than on
        // dismiss.
        let app = launch(startingIn: "light")
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 12))
        openSettings(app)
        setDarkMode(true, in: app)
        closeSettingsAndEverything(app)
        app.terminate()

        // Relaunched with no appearance argument at all, so the only thing that can make this
        // dark is what was persisted.
        let relaunched = launch()
        XCTAssertTrue(relaunched.buttons["start-button"].waitForExistence(timeout: 12))

        XCTAssertLessThan(
            brightnessOfTheScreen(), 0.35,
            "dark mode should still be on after a relaunch"
        )

        // Put it back, so this cannot darken whatever runs next.
        openSettings(relaunched)
        setDarkMode(false, in: relaunched)
        relaunched.buttons["settings-close-button"].tap()
    }
}
