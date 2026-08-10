import Foundation

/// Whether the Dark mode switch is reachable in Settings.
///
/// **It is not in a shipped build, and that is deliberate.** The same shape as D-015's paywall:
/// the machinery is complete and tested where it can be, and the control is not shown, because a
/// switch that does nothing is the product-side version of fabricating functionality.
///
/// ## What was known before this session
///
/// The preference stores, round-trips, rejects unknown values and maps to a `ColorScheme`; all of
/// that is covered by `AppearancePreferenceTests`. `NextPalette` has always declared both
/// appearances and `NextPaletteTests` holds every pair to 4.5:1 in each.
///
/// What never worked was the switch. Four CI rounds measured a mean screen brightness of
/// **0.8067215686274509 — identical to sixteen digits every time** after flipping it, across four
/// implementations: `preferredColorScheme` at the scene root; a `UIViewRepresentable` that was
/// never attached to a window; `UIApplication.connectedScenes`; and moving the read out of
/// `NEXTApp.body` into `RootView`.
///
/// ## What the evidence actually separates
///
/// Those four rounds are not four failures of one mechanism. Two paths put NEXT into dark and
/// they behave differently, which nobody had separated:
///
/// - **At launch** (`-ui-appearance dark`, set in `NEXTApp.init` before any body runs) the
///   rendering *does* change. Run 31364113774 is the proof: `testTheCardScreensPassTheAudit`
///   `InDarkMode` failed with two contrast issues on a screen whose light equivalent passes.
///   Something switched.
/// - **At runtime**, flipping the switch changed nothing measurable at all.
///
/// So the broken link is between the write and the render, not in the appearance machinery.
/// `WindowAppearance.apply` was also running off the main actor for every one of those rounds —
/// the Release step's warnings-as-errors is what finally said so, one commit *after* the gate
/// closed, so the current implementation has never actually been measured.
///
/// ## How it gets opened
///
/// `proofArgument` makes the switch reachable **under `-ui-testing` only**, so `AppearanceUITests`
/// can drive the real control and measure the real pixels without the control being shipped. A
/// normal build has no way to set a launch argument, so `isShipped` is the only thing a user can
/// reach. Flip `isShipped` to `true` — and delete nothing else — once those tests are green.
///
/// While it is closed the App Store set's sixth frame is captured in **light**, and the listing
/// may not claim a dark mode (D-024, D-027).
enum AppearanceAvailability {

    /// The shipped answer. Flip to `true` only alongside a green `AppearanceUITests`.
    private static let isShipped = false

    /// Opens the gate for a UI-testing launch, so the proof can drive the control a user would.
    ///
    /// Test scaffolding, and confined to it in the same way `-ui-seed` and `-ui-store-name` are:
    /// it does nothing unless `-ui-testing` is also present.
    static let proofArgument = "-ui-dark-mode-proof"

    /// Read once. It is consulted in two view bodies, and a launch's arguments cannot change
    /// while it is running.
    static let isDarkModeReachable: Bool = {
        if isShipped { return true }
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(NEXTApp.uiTestingArgument) && arguments.contains(proofArgument)
    }()
}
