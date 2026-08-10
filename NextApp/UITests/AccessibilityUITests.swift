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

    private func launch(contentSize: String? = nil, appearance: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        if let appearance {
            app.launchArguments += ["-ui-appearance", appearance]
        }
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

        // Waits for hittable, and confirms onboarding actually left. Existing is not the same as
        // being tappable — a lesson this suite has already recorded — and a tap that lands before
        // the view is ready is swallowed silently, surfacing 100 seconds later as "empty-add-button
        // does not exist" with onboarding still on screen. That is what it did on a loaded runner
        // once the suite grew long enough for this to run last.
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: skip
        )
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 15), .completed)
        skip.tap()

        // Up to three taps, with a fresh expectation each time — an `XCTestExpectation` is
        // single-use and reusing one is its own bug.
        //
        // The failure mode is a tap that XCUITest synthesises and the app never receives on a
        // loaded runner, and this suite has now seen it at three different points: Skip here,
        // an Everything row, and Task Detail's save button. Waiting longer for a tap that never
        // registered only makes the report slower, so the answer is to tap again. The assertion
        // is unchanged and is the one that matters: onboarding has to actually leave.
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
    /// That was recorded as the system's rendering rather than NEXT's colour, in the same
    /// category as navigation-bar buttons that do not scale. **Measuring the pixels says it is
    /// neither**: the header is drawn at 7.14:1 and the audit reports it anyway — see
    /// `testTheFirstSectionHeaderIsReportedButDrawnCorrectly`.
    ///
    /// These three screens therefore no longer need contrast excluded, because `audit` now
    /// overrules a contrast verdict its own pixels contradict. Moving them into the enforced set
    /// is left as its own change rather than folded into the Dark mode work: it may surface real
    /// failures on screens nothing has ever held to this bar, and that deserves its own round.
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
    /// Whether a "no description" issue is about system chrome rather than about NEXT.
    ///
    /// The concrete case is the keyboard's QuickType bar. Capture focuses its field on appear, so
    /// the keyboard is up while the audit runs — which is the right state to audit, because it is
    /// the state the user is in and the reason the action bar sits in a safe-area inset — and the
    /// audit walks the bar's three unlabelled 140 × 44 suggestion slots, which no app can label,
    /// style or remove.
    ///
    /// **Identified by what it is, not by where it is.** A first attempt scoped this by frame
    /// against `app.keyboards`, and it did not fire: the QuickType bar sits directly *above* the
    /// keyboard's own rect, and `CGRect.intersects` is false for rectangles that merely touch.
    /// Chasing that with a fudge factor would have meant a number tuned to one runner's screen
    /// size.
    ///
    /// Three conditions, deliberately narrow. Every element NEXT draws that could carry a
    /// description carries an accessibility identifier, and the check is applied only to
    /// `sufficientElementDescription` — so contrast and hit-region issues on the same element are
    /// still reported, and an unlabelled element of NEXT's own still fails, which is the whole
    /// point of that audit type.
    private func isSystemChrome(_ element: XCUIElement) -> Bool {
        element.identifier.isEmpty && element.label.isEmpty && element.elementType == .other
    }

    /// The margin a pixel measurement must clear before it is allowed to overrule the audit.
    ///
    /// 4.5:1 is the requirement; this is higher because `drawnContrast` quantises to five bits a
    /// channel to stop an anti-aliased fringe fragmenting into hundreds of colours, and that moves
    /// a ratio by a percent or two either way. An element measured between 4.5 and 5.0 is reported
    /// as a failure rather than argued about.
    private static let overrulingMargin: CGFloat = 5.0

    /// Audits the screen, and returns the contrast issues whose **pixels** clear the bar.
    @discardableResult
    private func audit(
        _ app: XCUIApplication,
        _ screen: String,
        for types: XCUIAccessibilityAuditType = AccessibilityUITests.enforced,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [String] {
        var issues: [String] = []
        var overruled: [String] = []

        // Taken once, before the audit walks anything, so every contrast issue is read against
        // the same frame the audit judged rather than against a screen that has since moved on.
        let screenshot = XCUIScreen.main.screenshot().image

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

                // The system keyboard is not NEXT's screen. See `isSystemChrome`.
                if issue.auditType == .sufficientElementDescription,
                   let element,
                   self.isSystemChrome(element) {
                    return true
                }

                // What it is actually drawn in, and — where that clears the bar with margin —
                // the reason this is not treated as a failure.
                //
                // The audit's contrast check is a heuristic over the render tree, and it is
                // measurably wrong on this app in both appearances: it reports Settings' first
                // section header, drawn at 7.14:1, and Today's empty state in dark, drawn at
                // 6.90:1. WCAG asks about what a reader sees, and what a reader sees is the
                // pixels. So the pixels decide, and every overruled verdict is printed rather
                // than swallowed — this is the third filter in this handler and the only one
                // backed by a measurement rather than by an argument.
                //
                // It can only ever *remove* a failure whose evidence contradicts it. An element
                // the audit reports and the pixels also fail still fails, which is the case this
                // check exists to keep honest.
                var drawn = ""
                if issue.auditType == .contrast, let frame = element?.frame {
                    let measured = drawnContrast(in: frame, of: screenshot)
                    if let ratio = measured.ratio, ratio >= Self.overrulingMargin {
                        overruled.append("\(element?.label ?? "—") — \(measured.description)")
                        return true
                    }
                    drawn = "\n        drawn: \(measured.description)"
                }

                issues.append(
                    """
                    • \(issue.auditType)
                        id: \(element?.identifier ?? "—")
                        label: \(element?.label ?? "—")
                        type: \(element.map { "\($0.elementType.rawValue)" } ?? "—")
                        frame: \(element.map { "\($0.frame)" } ?? "—")
                        detail: \(issue.compactDescription)\(drawn)
                    """
                )
                return true
            }
        } catch {
            issues.append("• the audit itself failed: \(error)")
        }

        for overruledIssue in overruled {
            print("AUDIT [\(screen)] contrast reported, pixels disagree: \(overruledIssue)")
        }

        guard !issues.isEmpty else { return overruled }

        XCTFail(
            "\(screen) — \(issues.count) accessibility issue(s):\n" + issues.joined(separator: "\n"),
            file: file,
            line: line
        )
        return overruled
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

    func testCaptureConfirmationPassesTheAudit() {
        // The audit stopped at the writing stage, which meant it never reached the app's only
        // state-carrying symbol: the include/exclude circle beside each extracted task, whose
        // meaning is entirely in whether it is filled. `sufficientElementDescription` is exactly
        // the check for that, and this screen was the one place it was not being run.
        let app = launch()
        skipOnboarding(app)
        app.buttons["empty-add-button"].tap()

        let field = app.textFields["capture-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Chem test monday. Email professor.")

        let extract = app.buttons["capture-extract-button"]
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: extract
        )
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 10), .completed)
        extract.tap()

        XCTAssertTrue(app.buttons["confirmation-accept-button"].waitForExistence(timeout: 10))

        audit(app, "Capture Confirmation")
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

        // This tap has been dropped twice on a loaded runner and reported 80 seconds later as a
        // missing save button. `isHittable` is *not* the verdict, deliberately: waiting on it
        // failed for ten seconds on a row that has been tapped successfully for six sessions, so
        // making a predicate that is wrong the reason a test fails only moves the flake. What is
        // asserted is the thing the test needs — that Task Detail opened — with one retry,
        // because the failure mode is a swallowed tap and waiting longer for one that never
        // registered just makes the report slower.
        let row = app.buttons["task-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        _ = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "isHittable == true"), object: row
            )],
            timeout: 5
        )
        row.tap()

        let save = app.buttons["detail-save-button"]
        if !save.waitForExistence(timeout: 8) {
            row.tap()
            XCTAssertTrue(save.waitForExistence(timeout: 8), "the task should open")
        }

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

    // MARK: The dark appearance

    func testTheCardScreensPassTheAuditInDarkMode() {
        // Until this existed, nothing had ever *rendered* NEXT in dark. `NextPaletteTests`
        // resolves every token pair in both appearances and asserts 4.5:1 against the values,
        // which is a claim about the palette, not about the screens — and the audit's own first
        // run proved how far apart those two things can be: the palette was correct throughout
        // while four classes of defect sat in the rendering.
        //
        // Driven by NEXT's own appearance rather than the simulator's.
        // `XCUIDevice.shared.appearance = .dark` does not take effect on this runner even with a
        // wait — the brightness check below measured 0.81, fully light, on the round that proved
        // it. The app's own setting is both the thing users have and the thing that works.
        let app = launch(appearance: "dark")
        skipOnboarding(app)

        XCTAssertTrue(app.buttons["empty-add-button"].waitForExistence(timeout: 10))

        // Before auditing anything, prove the screen actually went dark. Without this the test
        // is worthless in the exact case it exists for: the palette clears 4.5:1 in both
        // appearances, so an audit that quietly ran in light mode passes and reports nothing.
        XCTAssertLessThan(
            meanBrightness(of: XCUIScreen.main.screenshot().image), 0.35,
            "dark mode did not take effect, so this audit would prove nothing"
        )

        audit(app, "Today empty, dark")

        captureOneTask(app)
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 10))
        audit(app, "Today recommending, dark")

        app.buttons["im-stuck-button"].tap()
        XCTAssertTrue(app.buttons["rescue-path-tooMuch"].waitForExistence(timeout: 5))
        audit(app, "Rescue, dark")

        app.buttons["rescue-close-button"].tap()
        XCTAssertTrue(app.buttons["start-button"].waitForExistence(timeout: 5))
        app.buttons["start-button"].tap()
        XCTAssertTrue(app.buttons["focus-start-button"].waitForExistence(timeout: 5))
        audit(app, "Focus, dark")
    }

    // MARK: Contrast and Dynamic Type — tracked, not yet enforced

    func testTheFirstSectionHeaderIsReportedButDrawnCorrectly() {
        // D-021 recorded this as a system-rendering defect NEXT could not fix: one contrast
        // failure on each `List`/`Form` screen, always the first section header, always directly
        // beneath the navigation bar, which SwiftUI was said to render against the bar's material
        // whatever colour it is given.
        //
        // The pixels say otherwise. The header is drawn at **7.14:1** — 505048 on F0F0F0, the
        // palette's own ink on the grouped background — and the audit reports it anyway. So what
        // is wrong here is the audit's verdict, not the rendering, which is a materially
        // different claim from the one D-021 recorded and is why that entry now carries a
        // correction.
        //
        // Both halves are pinned. If SwiftUI ever stops reporting it the count drops to zero and
        // this fails, which is the tripwire the strict `XCTExpectFailure` used to provide; if the
        // pixels ever stop clearing the bar the audit stops being overruled and the screen fails
        // outright.
        let app = launch()
        skipOnboarding(app)
        captureOneTask(app)
        app.buttons["everything-button"].tap()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 5))
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["settings-close-button"].waitForExistence(timeout: 5))

        let overruled = audit(app, "Settings' first section header", for: [.contrast])

        XCTAssertEqual(
            overruled.count, 1,
            "the audit should still report exactly one contrast issue here whose pixels are fine — it reported \(overruled.count): \(overruled)"
        )
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
