import XCTest

/// Dark mode, driven the way a user drives it, and judged on the pixels.
///
/// The unit tests store the choice and map it to a `ColorScheme`; both would pass against a
/// setting that is saved perfectly and applied to nothing — and for four CI rounds, that is
/// exactly what shipped. So every claim here is a measurement of what was drawn.
///
/// These tests are what opened the gate. While they were failing the switch was hidden from
/// users behind `AppearanceAvailability`; that type is gone, because the answer it held is now
/// "yes" and a constant nobody can change is not a gate.
///
/// ## The order these run in is the argument they make
///
/// Each test rules out one explanation for the previous rounds, so a failure says which link
/// broke rather than only that the screen was the wrong colour:
///
/// 1. the measurement can tell two screens apart at all — otherwise every number below is void;
/// 2. an appearance chosen **at launch** reaches the pixels — that is the mechanism;
/// 3. an appearance chosen **at runtime** reaches the pixels — that is the switch;
/// 4. and back again, because a one-way switch is not a switch;
/// 5. and it survives being killed.
///
/// Every measurement also prints `AppearanceProbe`'s readout of the whole chain — the preference
/// the root saw, SwiftUI's `colorScheme`, the window's override, the current trait collection and
/// the palette's resolved values. That is diagnosis, not evidence: the pixels are the evidence.
@MainActor
final class AppearanceUITests: XCTestCase {

    /// A screen NEXT considers dark is well under this; the light desk measures around 0.8.
    private static let dark: CGFloat = 0.35
    private static let light: CGFloat = 0.5

    override func setUp() {
        super.setUp()
        // Deliberately *not* false, which is what the rest of the suite uses. Every assertion
        // here is a measurement, and stopping at the first one throws away the readings that say
        // why it failed — which is how four rounds produced one number and no diagnosis. A
        // failed switch should still be carried through to a relaunch, because what the relaunch
        // renders is what says whether the write landed and only the render was lost.
        continueAfterFailure = true
    }

    // MARK: Driving the app

    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-seed", "essay", "-ui-appearance-probe"
        ] + extraArguments
        app.launch()
        skipOnboarding(app)
        XCTAssertTrue(
            app.buttons["start-button"].waitForExistence(timeout: 15),
            "the seeded task should be recommended"
        )
        return app
    }

    private func skipOnboarding(_ app: XCUIApplication) {
        let skip = app.buttons["onboarding-skip-button"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: skip
        )
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 15), .completed)

        // Existing is not the same as being tappable, and a dropped Skip surfaces much later as
        // a missing button on a screen that never appeared. Up to three taps, with a fresh
        // expectation each time, for the reason spelled out in `AccessibilityUITests`.
        for attempt in 1...3 {
            skip.tap()
            let gone = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: skip
            )
            if XCTWaiter().wait(for: [gone], timeout: 8) == .completed { return }
            print("ONBOARDING skip tap \(attempt) did not register")
        }

        XCTFail("onboarding is still on screen after three taps on Skip")
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

    /// Flips the switch, and **checks that it flipped**.
    ///
    /// The version of this that ran for four rounds tapped and moved on. A tap that is silently
    /// dropped and a fix that silently does nothing produce the identical failure — a light
    /// screen — and there was nothing in the suite that could tell them apart.
    private func setDarkMode(_ on: Bool, in app: XCUIApplication) {
        let toggle = app.switches["settings-dark-mode-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "Settings should offer Dark mode")

        // Read first, so asking for a state it is already in is a no-op rather than a reversal.
        guard isOn(toggle) != on else { return }

        // Tapped by coordinate, on the switch itself — and this is the whole reason Dark mode
        // looked broken for four rounds.
        //
        // `toggle.tap()` does **not** flip it, which is measured rather than assumed. A `Toggle`
        // in a `Form` is exposed as one Switch element spanning the entire row, `.tap()` lands in
        // the middle of that — on the label — and in run 31390918616 it left the switch reading
        // its old value on every one of five attempts. Deterministic, not flaky. The old test
        // tapped and moved on, so a tap that never landed and a fix that changed nothing produced
        // the identical light screen, and nothing in the suite could tell them apart.
        //
        // This is where a finger goes, so it is the more faithful interaction, not a workaround.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()

        XCTAssertTrue(
            settles(toggle, to: on),
            "the Dark mode switch should now read \(on ? "on" : "off"), not \(toggle.value ?? "nothing")"
        )
    }

    private func settles(_ toggle: XCUIElement, to on: Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", on ? "1" : "0"), object: toggle
        )
        return XCTWaiter().wait(for: [expectation], timeout: 3) == .completed
    }

    private func isOn(_ toggle: XCUIElement) -> Bool {
        (toggle.value as? String) == "1"
    }

    // MARK: Measuring

    private func settle() {
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "settle")], timeout: 0.9)
    }

    /// Brightness of what is on screen, with the probe's readout recorded beside it.
    ///
    /// Both screenshot routes are measured. Whether `XCUIScreen.main.screenshot()` on this runner
    /// hands back the app's window or a cached compositor frame was one of the two standing
    /// suspects, and `app.screenshot()` asks a different question of a different object. They have
    /// agreed to sixteen digits on every reading so far; if they ever disagree, the disagreement
    /// is the finding.
    @discardableResult
    private func measure(_ app: XCUIApplication, _ moment: String) -> CGFloat {
        settle()
        let screen = meanBrightness(of: XCUIScreen.main.screenshot().image)
        let window = meanBrightness(of: app.screenshot().image)

        let probe = app.staticTexts["appearance-probe"]
        let readout = probe.exists ? probe.label : "probe absent"
        let line = "APPEARANCE [\(moment)] screen=\(screen) app=\(window) \(readout)"
        print(line)
        XCTContext.runActivity(named: line) { _ in }

        return screen
    }

    // MARK: 1 — the measurement itself

    func testTheMeasurementCanTellTwoScreensApart() {
        // Every other number in this file is void if the capture is a frozen frame, and a frozen
        // frame is indistinguishable from "the fix did nothing" — which is the exact ambiguity
        // four rounds of identical readings could not resolve. Two screens, one appearance, no
        // dark mode involved: if these come back equal, the screenshot is the broken thing.
        let app = launch()
        let today = measure(app, "today, light")

        app.buttons["start-button"].tap()
        XCTAssertTrue(app.buttons["focus-start-button"].waitForExistence(timeout: 10))
        let focus = measure(app, "focus, light")

        XCTAssertGreaterThan(
            abs(today - focus), 0.005,
            "two visibly different screens measured the same — the capture is not live"
        )
    }

    // MARK: 2 — the mechanism

    func testLaunchingInDarkRendersDark() {
        // Separated from the switch deliberately. The preference is set in `NEXTApp.init`, before
        // any body runs, so this exercises applying an appearance without exercising observing a
        // change to one. When this passes and the next test fails, the fault is in the change.
        let app = launch(["-ui-appearance", "dark"])
        XCTAssertLessThan(
            measure(app, "today, launched dark"), Self.dark,
            "an app told at launch to be dark must render dark"
        )
    }

    func testLaunchingInLightRendersLight() {
        let app = launch(["-ui-appearance", "light"])
        XCTAssertGreaterThan(
            measure(app, "today, launched light"), Self.light,
            "light is the default and must render light"
        )
    }

    // MARK: 3 and 4 — the switch, both ways

    func testTurningOnDarkModeDarkensTheWholeApp() {
        let app = launch(["-ui-appearance", "light"])
        XCTAssertGreaterThan(
            measure(app, "before"), Self.light,
            "Today should start light, because light is the default"
        )

        openSettings(app)
        setDarkMode(true, in: app)

        // Back on Today, where the change has to be visible — not only inside the sheet that set
        // it. The choice is made three levels down; it is applied at the scene root precisely so
        // that every screen hears about it.
        closeSettingsAndEverything(app)

        XCTAssertLessThan(
            measure(app, "after turning dark on"), Self.dark,
            "turning on Dark mode must darken Today itself, not only the Settings sheet"
        )
    }

    func testTurningDarkModeOffLightensTheWholeApp() {
        // A switch that only goes one way is not a switch, and the failure is worse than not
        // shipping one: somebody who tries dark and dislikes it would be stuck in it.
        let app = launch(["-ui-appearance", "dark"])
        XCTAssertLessThan(measure(app, "before"), Self.dark)

        openSettings(app)
        setDarkMode(false, in: app)
        closeSettingsAndEverything(app)

        XCTAssertGreaterThan(
            measure(app, "after turning dark off"), Self.light,
            "turning Dark mode off must return the whole app to light"
        )
    }

    // MARK: 5 — across a relaunch

    func testTheChosenAppearanceSurvivesARelaunch() {
        // A setting that visibly changes the app and then forgets is worse than one never
        // offered, which is why the choice is written through as it is made rather than on
        // dismiss.
        //
        // The earlier version of this test was deleted as unprovable, and it was: every
        // `-ui-testing` launch reset the preference, so a relaunch could only ever measure the
        // harness. `-ui-keep-appearance` makes the harness *stop interfering* instead of
        // supplying the answer — the second launch is told nothing at all, so the only thing that
        // can make it dark is what the first one stored.
        let app = launch(["-ui-appearance", "light"])
        openSettings(app)
        setDarkMode(true, in: app)
        closeSettingsAndEverything(app)
        XCTAssertLessThan(measure(app, "dark, before terminating"), Self.dark)
        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launchArguments = [
            "-ui-testing", "-ui-seed", "essay", "-ui-appearance-probe", "-ui-keep-appearance"
        ]
        relaunched.launch()
        skipOnboarding(relaunched)
        XCTAssertTrue(relaunched.buttons["start-button"].waitForExistence(timeout: 15))

        XCTAssertLessThan(
            measure(relaunched, "dark, after relaunching"), Self.dark,
            "Dark mode should still be on after a relaunch"
        )

        // Put it back. Every other test resets the preference on launch, so this is belt and
        // braces rather than load-bearing — but a test that leaves the simulator in a state it
        // did not find it in is one bad launch argument away from darkening someone else's run.
        openSettings(relaunched)
        setDarkMode(false, in: relaunched)
        relaunched.buttons["settings-close-button"].tap()
    }

    // MARK: Reachable

    func testAnOrdinaryLaunchOffersTheSwitch() {
        // The inverse of the tripwire that stood here while Dark mode was hidden, and it earns
        // its place for the same reason that one did: every other test in this file passes a
        // launch argument of some kind, so all of them would still be green if the control were
        // quietly put back behind a flag. Nothing here is passed but `-ui-testing`.
        //
        // Asserted through the interface rather than against a constant, because a UI test runs
        // out of process and cannot import the app module — which is also why it is the right
        // check: it answers whether the *user* can see the switch.
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        skipOnboarding(app)
        openSettings(app)

        XCTAssertTrue(
            app.switches["settings-dark-mode-toggle"].waitForExistence(timeout: 8),
            "Settings must offer Dark mode — it is shipped, and it is measured to work"
        )
    }
}
