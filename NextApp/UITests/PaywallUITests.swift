import XCTest

/// The paywall, and the fact that a normal build has no way to it.
///
/// NEXT+ unlocks nothing today (`FeatureGate.oneDotZero`), so offering it for sale would be
/// offering something that does not exist. The screen is finished and verified anyway, behind a
/// launch argument — see `MonetisationAvailability` and `DECISIONS.md` D-015. These two tests are
/// what stop that arrangement being a claim: one proves it is unreachable, the other proves the
/// thing behind the flag actually works.
final class PaywallUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(storeKitTesting: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = storeKitTesting
            ? ["-ui-testing", "-storekit-testing"]
            : ["-ui-testing"]
        app.launch()

        let skip = app.buttons["onboarding-skip-button"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "a first run should show onboarding")
        skip.tap()

        return app
    }

    /// Captures one task, then opens Settings.
    ///
    /// Settings is reached from Everything, and Everything is reached from a Today that has
    /// something on it — so a task has to exist first.
    private func openSettings(_ app: XCUIApplication) {
        let add = app.buttons["empty-add-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let field = app.textFields["capture-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Email Professor Adeyemi")

        let save = app.buttons["capture-save-single-button"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isHittable)
        save.tap()

        let done = app.buttons["capture-done-button"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        done.tap()

        XCTAssertTrue(app.buttons["everything-button"].waitForExistence(timeout: 10))
        app.buttons["everything-button"].tap()

        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 5))
        app.buttons["settings-button"].tap()

        XCTAssertTrue(
            app.buttons["settings-close-button"].waitForExistence(timeout: 5),
            "Settings should open"
        )
    }

    /// Scrolls a `Form` until the named element exists.
    ///
    /// A `Form` renders its rows lazily, so a control below the fold genuinely does not exist yet.
    /// Scrolling to it is part of checking it is reachable rather than a workaround.
    @discardableResult
    private func scroll(to identifier: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]
        for _ in 0..<6 {
            if element.exists { return element }
            app.swipeUp()
        }
        return element
    }

    func testANormalRunHasNoWayToThePaywall() {
        let app = launch(storeKitTesting: false)
        openSettings(app)

        // Scrolled through the whole form rather than glanced at the top of it, so this fails for
        // the right reason if the row is ever added back.
        scroll(to: "settings-next-plus", in: app)

        XCTAssertFalse(
            app.descendants(matching: .any)["settings-next-plus"].exists,
            "NEXT+ must not be on sale while it unlocks nothing"
        )
    }

    func testThePaywallOpensAndAdvertisesNothingItDoesNotHave() {
        let app = launch(storeKitTesting: true)
        openSettings(app)

        let row = scroll(to: "settings-next-plus", in: app)
        XCTAssertTrue(row.exists, "the flag should make NEXT+ reachable")
        row.tap()

        // The screen's whole job today is to be honest about having nothing to sell.
        let explanation = app.descendants(matching: .any)["paywall-nothing-gated"]
        XCTAssertTrue(
            explanation.waitForExistence(timeout: 5),
            "the paywall should say plainly that nothing is behind it"
        )

        // Restore is not optional — someone who paid must be able to get it back without paying
        // again, and App Review requires the control regardless.
        XCTAssertTrue(
            scroll(to: "paywall-restore", in: app).exists,
            "the paywall must offer a way to restore a previous purchase"
        )
    }
}
