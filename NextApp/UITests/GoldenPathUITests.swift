import XCTest

/// Tier 2 UI tests, run on the iOS Simulator.
///
/// The golden path from TESTING.md, as far as the app currently goes:
/// fresh install → empty state → capture → extraction → confirmation → recommendation → START →
/// Focus → Done → next recommendation.
///
/// Onboarding is included: it is reset on every UI-test launch, so each run passes through the
/// honest first run rather than bypassing it.
///
/// Still missing, and named here so the gap stays visible: relaunch-persistence. The UI target
/// gets a fresh in-memory store per launch, so that needs a different arrangement.
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

    /// Launches and steps through onboarding, leaving the app on Today.
    ///
    /// Onboarding is reset on every UI-test launch, so it is genuinely on screen each time —
    /// which is the honest first run, and worth passing through rather than bypassing.
    private func launchPastOnboarding() -> XCUIApplication {
        let app = launch()

        let skip = app.buttons["onboarding-skip-button"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "a first run should show onboarding")
        skip.tap()

        return app
    }

    /// Waits for a field to actually hold `expected`, then asserts it.
    ///
    /// A polled wait rather than a sleep: it returns as soon as the value is right, so the happy
    /// path costs nothing and only a genuine failure spends the full timeout.
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
            "the field should hold what was typed",
            file: file,
            line: line
        )
    }

    /// Chooses "Just start" on the Focus timer screen, so the session is running.
    private func startFocusWithoutTimer(_ app: XCUIApplication) {
        let justStart = app.buttons["focus-start-button"]
        XCTAssertTrue(
            justStart.waitForExistence(timeout: 5),
            "Focus should ask how long before starting a countdown"
        )
        justStart.tap()
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

        // Wait for the text to land rather than asserting immediately. `typeText` returns before
        // SwiftUI has necessarily processed every keystroke, and on a loaded CI machine this
        // read caught a half-typed "Email Pr". Checking that the field holds what was typed is
        // still worth doing — a field that silently ignores input leaves the save button
        // disabled and the failure surfaces several assertions later — it just has to be a wait
        // rather than a glance.
        expectValue(text, in: field, timeout: 10)

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

    func testColdStartIsMeasured() {
        // The release checklist asks for cold start to be *measured*, and nothing had ever
        // measured it. This records a number rather than asserting a threshold: a limit invented
        // here would be a number nobody chose, and the honest claim is "this is what it is on a
        // GitHub macOS runner", which is slower and busier than any phone a student owns.
        //
        // What it does check, structurally, is that the launch path completes without waiting on
        // anything — NEXT constructs no intelligence provider at launch and makes no network
        // request, so a launch that hung would show up here as an outlier rather than as a
        // support ticket.
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]

        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }

    func testOnboardingIsThreeScreensAndAsksForNothing() {
        // PRODUCT_SPEC.md §4.1: no account, no email, no profile, no survey, no quiz. The check
        // is that there is nothing to fill in — a text field appearing here would be the defect.
        let app = launch()

        let next = app.buttons["onboarding-continue-button"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields.count, 0, "onboarding must not ask for anything")
        XCTAssertEqual(app.secureTextFields.count, 0)

        next.tap()
        next.tap()
        next.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["empty-state"].waitForExistence(timeout: 10),
            "three taps should reach the app itself"
        )
    }

    func testFirstRunIsEmptyAndOffersAWayOut() {
        // NEXT must not invent tasks the student never wrote. An empty first run is correct —
        // an empty first run with no way forward is a dead end.
        let app = launchPastOnboarding()

        XCTAssertTrue(app.descendants(matching: .any)["empty-state"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["empty-add-button"].exists)
        XCTAssertFalse(app.buttons["start-button"].exists, "nothing should be recommended yet")
    }

    func testManualCaptureProducesSomethingToStart() {
        let app = launchPastOnboarding()

        captureOneTask(app, text: "Email Professor Adeyemi")

        XCTAssertTrue(
            app.buttons["start-button"].waitForExistence(timeout: 10),
            "a captured task should immediately become something to start"
        )
    }

    func testBrainDumpGoesThroughConfirmationBeforeAnythingIsSaved() {
        let app = launchPastOnboarding()

        app.buttons["empty-add-button"].tap()

        let field = app.textFields["capture-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("chem test monday, email professor, finish history slides friday")

        app.buttons["capture-extract-button"].tap()

        // Confirmation is not optional. Nothing has been written at this point.
        // Waits on the accept button rather than the container: a leaf control is what proves
        // the screen is usable, and container identifiers are the thing that already went wrong.
        let accept = app.buttons["confirmation-accept-button"]
        XCTAssertTrue(
            accept.waitForExistence(timeout: 15),
            "extraction must land on confirmation, not save straight away"
        )
        XCTAssertTrue(accept.isHittable)
        accept.tap()

        let done = app.buttons["capture-done-button"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
    }

    func testStartOpensFocusAndDoneReturnsWithANewRecommendation() {
        let app = launchPastOnboarding()
        captureOneTask(app, text: "Email Professor Adeyemi")

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
        app.buttons["start-button"].tap()
        startFocusWithoutTimer(app)

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

    func testFocusOffersATimerButDoesNotImposeOne() {
        // NEXT is not a Pomodoro app. The length is chosen before the clock starts, so nobody
        // is put on a countdown they did not ask for.
        let app = launchPastOnboarding()
        captureOneTask(app, text: "Read chapter four")

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
        app.buttons["start-button"].tap()

        XCTAssertTrue(app.buttons["focus-start-button"].waitForExistence(timeout: 5))
        for preset in [5, 15, 25, 45] {
            XCTAssertTrue(
                app.buttons["focus-timer-\(preset)"].exists,
                "the \(preset) minute preset should be offered"
            )
        }

        app.buttons["focus-timer-25"].tap()

        XCTAssertTrue(
            app.buttons["focus-pause-button"].waitForExistence(timeout: 5),
            "choosing a length should start a pausable session"
        )
        XCTAssertTrue(app.buttons["focus-done-button"].exists)
    }

    func testStoppingFocusReturnsWithoutCompleting() {
        let app = launchPastOnboarding()
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

    func testTheCardAlwaysSaysWhyThisOne() {
        // The recommendation is never an unknowable oracle — PRODUCT_SPEC.md §4.4. What changed
        // is where the answer is: it used to be an alert behind a "Why this?" link, and that link
        // was a modal repeating the card for any task with a deadline. The explanation is now on
        // the card itself, so this asserts it is *visible* rather than that a control produces it.
        //
        // A captured task has no deadline and no estimate, which is the case the old alert was
        // the only place to see — so this is also the state that used to hide its reason from a
        // user who never tapped.
        let app = launchPastOnboarding()
        captureOneTask(app, text: "Email Professor Adeyemi")

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))

        let reason = app.staticTexts["recommendation-reason"]
        XCTAssertTrue(
            reason.waitForExistence(timeout: 5),
            "the card must explain itself without being asked"
        )
        XCTAssertFalse(reason.label.isEmpty, "an empty explanation is not an explanation")

        XCTAssertFalse(
            app.buttons["why-this-button"].exists,
            "Why this? is retired — the card carries the reason now"
        )
    }

    func testEverySecondaryActionIsReachable() {
        let app = launchPastOnboarding()
        captureOneTask(app, text: "Email Professor Adeyemi")

        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
        for identifier in [
            "im-stuck-button", "something-else-button",
            "everything-button", "add-button"
        ] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists, "\(identifier) should be present")
            XCTAssertTrue(button.isHittable, "\(identifier) should be reachable by tap")
        }
    }

    func testTheOnlyTaskComesBackSayingItWasPassedOver() {
        // The other half of "Something else", and the sentence that stops NEXT looking like it was not
        // listening. With one task there is nothing else to offer, so the engine returns it —
        // finite penalty, by design — and the screen has to say so rather than re-serving it as
        // though nothing happened. The string existed and no test at any tier had ever read it.
        let app = launchPastOnboarding()
        captureOneTask(app, text: "Email Professor Adeyemi")

        XCTAssertTrue(app.buttons["something-else-button"].waitForExistence(timeout: 10))
        app.buttons["something-else-button"].tap()

        let reason = app.buttons["Can't do it right now"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        reason.tap()

        let notice = app.staticTexts["recently-rejected-notice"]
        XCTAssertTrue(
            notice.waitForExistence(timeout: 10),
            "re-serving the only task must acknowledge that it was passed over"
        )
    }

    func testATaskOpenedByLinkCanBeClosedWithoutASwipe() {
        // The deep-link sheet presents Task Detail as the root of its own stack, so it has no
        // back button — and Task Detail deliberately carries no Close button of its own. Until
        // this was fixed, a task opened from a tapped reminder or the widget could only be left
        // by swiping the sheet down, which is the one thing "no essential action is gesture-only"
        // forbids.
        //
        // Seeded rather than captured, because the link is opened from Today's first load: the
        // sheet has to have something to open. `-ui-seed-unreachable` is the existing fixture
        // that puts one real task in the store before the first read.
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-seed-unreachable", "-ui-open-recommended"]
        app.launch()

        let skip = app.buttons["onboarding-skip-button"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()

        let close = app.buttons["linked-task-close-button"]
        XCTAssertTrue(
            close.waitForExistence(timeout: 15),
            "a task opened by link must offer a way out that is not a gesture"
        )
        XCTAssertTrue(close.isHittable)
        close.tap()

        XCTAssertTrue(
            app.buttons["start-button"].waitForExistence(timeout: 10),
            "closing the linked task should return to Today"
        )
    }

    func testEverythingShowsWhatWasCaptured() {
        // Capture used to be a one-way door: a mistyped task was unreachable.
        let app = launchPastOnboarding()
        captureOneTask(app, text: "Email Professor Adeyemi")

        XCTAssertTrue(app.buttons["everything-button"].waitForExistence(timeout: 10))
        app.buttons["everything-button"].tap()

        XCTAssertTrue(
            app.buttons["everything-close-button"].waitForExistence(timeout: 5),
            "Everything should open"
        )
        XCTAssertTrue(
            app.staticTexts["Email Professor Adeyemi"].waitForExistence(timeout: 5),
            "the captured task should be listed"
        )
    }

    func testATaskCanBeOpenedAndEdited() {
        let app = launchPastOnboarding()
        captureOneTask(app, text: "Email Professor Adeyemi")

        app.buttons["everything-button"].tap()
        XCTAssertTrue(app.buttons["everything-close-button"].waitForExistence(timeout: 5))

        let row = app.buttons["task-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable, "the row must be tappable, not just present")
        row.tap()

        if !app.buttons["detail-save-button"].waitForExistence(timeout: 8) {
            XCTFail(
                """
                Tapping a task did not open its detail.
                TREE:
                \(app.debugDescription)
                """
            )
            return
        }
        XCTAssertTrue(app.textFields["detail-title-field"].exists)

        // Delete lives at the bottom of the form, below the fold. A Form renders its rows
        // lazily, so an off-screen control genuinely does not exist yet — scrolling to it is
        // part of checking it is reachable, not a workaround.
        let delete = app.buttons["detail-delete-button"]
        if !delete.exists { app.swipeUp() }
        XCTAssertTrue(
            delete.waitForExistence(timeout: 5),
            "delete should be reachable by scrolling the form"
        )
    }

    func testSettingsIsReachableAndAsksBeforeItActs() {
        // Notification permission must not be requested at launch. Reaching Settings and seeing
        // the switches should still not have prompted for anything.
        let app = launchPastOnboarding()
        captureOneTask(app, text: "Email Professor Adeyemi")

        app.buttons["everything-button"].tap()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 5))
        app.buttons["settings-button"].tap()

        XCTAssertTrue(
            app.buttons["settings-close-button"].waitForExistence(timeout: 5),
            "Settings should open"
        )
        XCTAssertTrue(app.switches["settings-deadline-toggle"].exists)
        XCTAssertTrue(app.switches["settings-daily-toggle"].exists)
        XCTAssertTrue(app.switches["settings-cloud-ai-toggle"].exists)

        // Cloud processing is off until explicitly turned on (PRIVACY.md).
        let cloud = app.switches["settings-cloud-ai-toggle"]
        XCTAssertEqual(cloud.value as? String, "0", "cloud processing must default to off")
    }

    func testImStuckOffersTheFourPathsAndAnswersOne() {
        // Rescue is a first-class feature, and never an open chatbot: four named paths only.
        let app = launchPastOnboarding()
        captureOneTask(app, text: "Finish the history essay")

        XCTAssertTrue(app.buttons["im-stuck-button"].waitForExistence(timeout: 10))
        app.buttons["im-stuck-button"].tap()

        for path in [
            "rescue-path-dontKnowHowToStart", "rescue-path-tooMuch",
            "rescue-path-notEnoughTime", "rescue-path-dontWantTo"
        ] {
            XCTAssertTrue(
                app.buttons[path].waitForExistence(timeout: 5),
                "\(path) should be offered"
            )
        }

        app.buttons["rescue-path-dontKnowHowToStart"].tap()

        XCTAssertTrue(
            app.buttons["rescue-start-button"].waitForExistence(timeout: 5),
            "choosing a path should produce something to do"
        )
    }
}
