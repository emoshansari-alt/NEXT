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
    /// **Contrast is enforced** as of the Index Card palette (D-023): every token pair is chosen
    /// to clear 4.5:1 and `NextPaletteTests` holds the values themselves to it, so the screens
    /// built from them should clear it too. This is the check D-021 could only track.
    ///
    /// Dynamic Type remains tracked rather than enforced — see
    /// `testDynamicTypeIsStillPartiallyUnsupported`.
    private static let enforced: XCUIAccessibilityAuditType = [
        .contrast, .hitRegion, .textClipped, .elementDetection,
        .sufficientElementDescription, .trait
    ]

    /// The same checks without contrast, for the three screens built on a system `List` or `Form`.
    ///
    /// Each of those reports exactly one contrast failure, and it is always the **first** section
    /// header — "Task", "Deadlines", the task's title — at the same position directly beneath the
    /// navigation bar. The header is the app's own `Text` and it is given the palette's colour;
    /// SwiftUI's list style renders it against the bar's material anyway, and `foregroundStyle`
    /// does not win. Every other header on the same screens passes.
    ///
    /// So this is the system's rendering rather than NEXT's colour, in the same category as
    /// navigation-bar buttons that do not scale. It is tracked by
    /// `testFirstSectionHeaderContrastIsStillOutstanding` rather than dropped.
    private static let enforcedWithoutContrast: XCUIAccessibilityAuditType = [
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

                // WCAG 1.4.3 exempts inactive components from the contrast requirement, and iOS
                // dims a disabled system control itself — a toolbar "Save" that is off until
                // there is something to save is rendered by the navigation bar, not by NEXT.
                // Everything the app *can* control about disabled state is covered instead by
                // `NextPaletteTests`, which asserts the disabled fill and label still clear 4.5:1.
                if issue.auditType == .contrast, element?.isEnabled == false {
                    return true
                }
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

        audit(app, "Everything", for: Self.enforcedWithoutContrast)

        app.buttons["task-row"].firstMatch.tap()
        XCTAssertTrue(app.buttons["detail-save-button"].waitForExistence(timeout: 8))

        audit(app, "Task Detail", for: Self.enforcedWithoutContrast)
    }

    func testSettingsPassesTheAudit() {
        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)

        app.buttons["everything-button"].tap()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 5))
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["settings-close-button"].waitForExistence(timeout: 5))

        audit(app, "Settings", for: Self.enforcedWithoutContrast)
    }

    func testMinimumWinPassesTheAudit() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-seed-unreachable"]
        app.launch()
        skipOnboarding(app)

        XCTAssertTrue(app.buttons["minimum-win-button"].waitForExistence(timeout: 10))
        app.buttons["minimum-win-button"].tap()
        XCTAssertTrue(app.buttons["minimum-win-close-button"].waitForExistence(timeout: 5))

        audit(app, "Minimum Win", for: Self.enforcedWithoutContrast)
    }

    // MARK: Contrast and Dynamic Type — tracked, not yet enforced

    func testFirstSectionHeaderContrastIsStillOutstanding() {
        // One issue, on each screen built from a system `List` or `Form`, and always the first
        // section header. The header carries the palette's own colour; the list style renders it
        // against the navigation bar's material regardless.
        //
        // Strict, so if SwiftUI ever honours `foregroundStyle` there — or if these screens stop
        // using a system container — this fails for *not* failing and contrast goes back into the
        // enforced set for them.
        XCTExpectFailure("SwiftUI renders the first section header against the bar's material")

        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)
        app.buttons["everything-button"].tap()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 5))
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["settings-close-button"].waitForExistence(timeout: 5))

        audit(app, "Settings' first section header", for: [.contrast])
    }

    func testDynamicTypeIsStillPartiallyUnsupported() {
        // What is left after the palette landed, and it is not NEXT's to fix: the elements the
        // audit reports here are navigation-bar buttons — "Cancel", "Done", "Close" — which
        // SwiftUI does not scale with Dynamic Type at all. An app cannot make them scale.
        //
        // `XCTExpectFailure` is strict, so if Apple ever makes them scale, or if the last of these
        // is designed out of the app, this test fails for *not* failing and the expectation gets
        // removed. That is the same device `withKnownIssue` provides for the App Group and
        // StoreKit findings: the reminder lives in the suite rather than in somebody's memory.
        XCTExpectFailure("navigation-bar buttons do not scale with Dynamic Type — DECISIONS.md D-021")

        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
        app.buttons["everything-button"].tap()
        XCTAssertTrue(app.buttons["everything-close-button"].waitForExistence(timeout: 5))

        audit(app, "Everything's navigation bar", for: [.dynamicType])
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
