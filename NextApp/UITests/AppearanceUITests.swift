import XCTest

/// Dark mode's user-facing half, which is currently unreachable on purpose.
///
/// `AppearanceAvailability.isDarkModeReachable` is false: the switch is not shown, because four
/// CI rounds proved the choice never changes what is rendered. The full diagnosis lives on that
/// type. What is left here is a tripwire, so the gate cannot be opened quietly.
@MainActor
final class AppearanceUITests: XCTestCase {

    func testTheDarkModeSwitchIsStillHidden() {
        // Asserted through the interface rather than against `AppearanceAvailability`, because
        // a UI test runs out of process and cannot import the app module — which is also why
        // this is the right check: it fails when the *user* can see the switch, whatever the
        // flag says.
        //
        // When it fails, somebody has made Dark mode reachable, and the test that proves it
        // works has to come back with it. That test is in this file's git history: launch light,
        // open Settings, flip `settings-dark-mode-toggle`, return to Today, and assert
        // `meanBrightness` is below 0.35. Do not re-enable the switch without it — the whole
        // reason this is gated is that everything except a pixel measurement passed.
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let skip = app.buttons["onboarding-skip-button"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        skip.tap()

        app.buttons["everything-button"].tap()
        let settings = app.buttons["settings-button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        XCTAssertTrue(app.buttons["settings-close-button"].waitForExistence(timeout: 8))

        XCTAssertFalse(
            app.switches["settings-dark-mode-toggle"].exists,
            "Settings must not offer a switch that changes nothing"
        )
    }
}
