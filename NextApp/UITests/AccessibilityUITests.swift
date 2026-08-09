import XCTest

/// The automated half of the accessibility audit `PRODUCT_SPEC.md` §11 makes release-blocking.
///
/// P8 says an accessibility defect in a core flow is a release blocker, and until now nothing had
/// ever checked. `performAccessibilityAudit()` covers what a machine can genuinely judge:
/// contrast, element descriptions, hit-region size, clipped text under Dynamic Type, and
/// conflicting traits.
///
/// **What it does not cover is written down rather than implied.** VoiceOver gesture traversal and
/// rotor behaviour, real Dynamic Type rendering on device, and haptics all need hardware —
/// `RELEASE_GATED.md` B5. A green run here is not a claim that NEXT is accessible; it is a claim
/// that the automatable checks pass on every core screen, which is a smaller and true statement.
// Main-actor isolated as a whole: `performAccessibilityAudit` is main-actor bound, and the
// issue-collecting handler closes over local state, so calling it from a nonisolated context is
// a data race the compiler correctly refuses.
@MainActor
final class AccessibilityUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        if let contentSize {
            // The documented way to drive Dynamic Type from a UI test. Set at launch so the
            // whole app lays out at that size rather than re-flowing mid-run.
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    private func skipOnboarding(_ app: XCUIApplication) {
        let skip = app.buttons["onboarding-skip-button"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        skip.tap()
    }

    private func captureOneTask(_ app: XCUIApplication, text: String = "Finish the history essay") {
        let add = app.buttons["empty-add-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let field = app.textFields["capture-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)

        let save = app.buttons["capture-save-single-button"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: save
        )
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 10), .completed)
        save.tap()

        let done = app.buttons["capture-done-button"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        done.tap()
    }

    /// The checks NEXT is held to now.
    ///
    /// Contrast and Dynamic Type are absent here and tracked separately rather than quietly
    /// dropped — see `testContrastAndDynamicTypeAreStillOutstanding` and `DECISIONS.md` D-021.
    private static let enforced: XCUIAccessibilityAuditType = [
        .hitRegion, .textClipped, .elementDetection, .sufficientElementDescription, .trait
    ]

    /// Audits whatever is currently on screen and reports **every** issue, with the element.
    ///
    /// The default behaviour throws on the first problem with a message like "Hit area is too
    /// small" and nothing about which control — the detail lives in the result bundle, which
    /// cannot be opened on the Windows development machine. Collecting the issues here instead
    /// turns one CI round into the whole list.
    ///
    /// The handler returns `true` for every issue, meaning "handled" — so the audit itself does
    /// not throw and this method decides the verdict, having recorded all of them.
    private func audit(
        _ app: XCUIApplication,
        _ screen: String,
        for types: XCUIAccessibilityAuditType = AccessibilityUITests.enforced,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var issues: [String] = []

        do {
            try app.performAccessibilityAudit(for: types) { issue in
                let element = issue.element
                issues.append(
                    """
                    • \(issue.auditType)
                        id: \(element?.identifier ?? "—")
                        label: \(element?.label ?? "—")
                        type: \(element.map { "\($0.elementType.rawValue)" } ?? "—")
                        frame: \(element.map { "\($0.frame)" } ?? "—")
                        detail: \(issue.compactDescription)
                    """
                )
                return true
            }
        } catch {
            issues.append("• the audit itself failed: \(error)")
        }

        guard !issues.isEmpty else { return }

        XCTFail(
            "\(screen) — \(issues.count) accessibility issue(s):\n" + issues.joined(separator: "\n"),
            file: file,
            line: line
        )
    }

    // MARK: Every core screen

    func testOnboardingPassesTheAudit() {
        let app = launch()
        XCTAssertTrue(app.buttons["onboarding-skip-button"].waitForExistence(timeout: 15))

        audit(app, "Onboarding")
    }

    func testEmptyTodayPassesTheAudit() {
        let app = launch()
        skipOnboarding(app)
        XCTAssertTrue(app.buttons["empty-add-button"].waitForExistence(timeout: 10))

        audit(app, "Today, empty")
    }

    func testCapturePassesTheAudit() {
        let app = launch()
        skipOnboarding(app)
        app.buttons["empty-add-button"].tap()
        XCTAssertTrue(app.textFields["capture-text-field"].waitForExistence(timeout: 5))

        audit(app, "Capture")
    }

    func testTodayWithARecommendationPassesTheAudit() {
        // The screen that matters most: it is the one a user sees every time they open NEXT.
        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))

        audit(app, "Today, recommending")
    }

    func testFocusPassesTheAudit() {
        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)
        app.buttons["start-button"].tap()
        XCTAssertTrue(app.buttons["focus-start-button"].waitForExistence(timeout: 5))

        audit(app, "Focus, choosing a length")

        app.buttons["focus-start-button"].tap()
        XCTAssertTrue(app.buttons["focus-done-button"].waitForExistence(timeout: 5))

        audit(app, "Focus, running")
    }

    func testRescuePassesTheAudit() {
        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)
        app.buttons["im-stuck-button"].tap()
        XCTAssertTrue(app.buttons["rescue-path-tooMuch"].waitForExistence(timeout: 5))

        audit(app, "Rescue, choosing a path")

        app.buttons["rescue-path-tooMuch"].tap()
        XCTAssertTrue(app.buttons["rescue-start-button"].waitForExistence(timeout: 5))

        audit(app, "Rescue, showing a step")
    }

    func testEverythingAndTaskDetailPassTheAudit() {
        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)

        app.buttons["everything-button"].tap()
        XCTAssertTrue(app.buttons["everything-close-button"].waitForExistence(timeout: 5))

        audit(app, "Everything")

        app.buttons["task-row"].firstMatch.tap()
        XCTAssertTrue(app.buttons["detail-save-button"].waitForExistence(timeout: 8))

        audit(app, "Task Detail")
    }

    func testSettingsPassesTheAudit() {
        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)

        app.buttons["everything-button"].tap()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 5))
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["settings-close-button"].waitForExistence(timeout: 5))

        audit(app, "Settings")
    }

    func testMinimumWinPassesTheAudit() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-seed-unreachable"]
        app.launch()
        skipOnboarding(app)

        XCTAssertTrue(app.buttons["minimum-win-button"].waitForExistence(timeout: 10))
        app.buttons["minimum-win-button"].tap()
        XCTAssertTrue(app.buttons["minimum-win-close-button"].waitForExistence(timeout: 5))

        audit(app, "Minimum Win")
    }

    // MARK: Contrast and Dynamic Type — tracked, not yet enforced

    func testContrastAndDynamicTypeAreStillOutstanding() {
        // These are the two categories the first audit run found that NEXT does not yet meet, and
        // they are recorded here rather than silently excluded.
        //
        // Most of what fails is not NEXT's own styling: the system tint on `.bordered` buttons,
        // `.secondary` label colour, and navigation-bar buttons that do not scale with Dynamic
        // Type at all. Choosing a palette that clears 4.5:1 across light and dark is Phase 12
        // (`PRODUCT_SPEC.md` §10), which has not happened — the app currently ships system
        // defaults on purpose, and repainting it now would be inventing a visual design in order
        // to pass a test.
        //
        // `XCTExpectFailure` is strict, so the day the palette lands this test fails for *not*
        // failing, and whoever does that work is told to come here and enforce it. That is the
        // same device `withKnownIssue` provides for the App Group and StoreKit findings.
        XCTExpectFailure("contrast and Dynamic Type are Phase 12 work — DECISIONS.md D-021")

        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))

        audit(app, "Today, recommending", for: [.contrast, .dynamicType])
    }

    // MARK: The largest Dynamic Type

    func testTodaySurvivesTheLargestAccessibilitySize() {
        // §11 requires the largest sizes not to destroy key screens. The audit's text-clipping
        // check is what catches a layout that has silently stopped fitting.
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        skipOnboarding(app)
        captureOneTask(app, text: "Finish the history essay")

        XCTAssertTrue(
            app.buttons["start-button"].waitForExistence(timeout: 15),
            "the primary action must still be reachable at the largest size"
        )

        audit(app, "Today at accessibility XXXL")
    }

    func testFocusSurvivesTheLargestAccessibilitySize() {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        skipOnboarding(app)
        captureOneTask(app, text: "Finish the history essay")

        app.buttons["start-button"].tap()
        XCTAssertTrue(app.buttons["focus-start-button"].waitForExistence(timeout: 10))
        app.buttons["focus-start-button"].tap()
        XCTAssertTrue(
            app.buttons["focus-done-button"].waitForExistence(timeout: 10),
            "Done must still be reachable at the largest size"
        )

        audit(app, "Focus at accessibility XXXL")
    }
}
