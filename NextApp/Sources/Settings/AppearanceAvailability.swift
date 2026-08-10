import Foundation

/// Whether the Dark mode switch is reachable in Settings.
///
/// **It is not, and that is deliberate.** The same shape as D-015's paywall: the machinery is
/// complete and tested where it can be, and the control is not shown, because a switch that does
/// nothing is the product-side version of fabricating functionality.
///
/// ## What works
///
/// The preference stores, round-trips, rejects unknown values and maps to a `ColorScheme`; all of
/// that is covered by `AppearancePreferenceTests` and passes. `NextPalette` has always declared
/// both appearances and `NextPaletteTests` holds every pair to 4.5:1 in each.
///
/// ## What does not
///
/// Nothing observed on screen ever changed. Four CI rounds measured a mean screen brightness of
/// **0.8067215686274509 — identical to sixteen digits every time**, before and after flipping the
/// switch, across four different implementations:
///
/// 1. `preferredColorScheme` at the scene root.
/// 2. A `UIViewRepresentable` setting `window?.overrideUserInterfaceStyle` — which never ran, as
///    the view was zero-sized and hidden so it was never attached to a window.
/// 3. `UIApplication.connectedScenes`, which needs no attachment.
/// 4. Moving the read out of `NEXTApp.body` into `RootView`, since `@Observable` tracking is
///    unreliable in an `App` body.
///
/// A number that does not move at all is not an insufficient fix; it is a fix that changes
/// nothing about what is rendered. The remaining suspects, for whoever picks this up: whether
/// `Color(uiColor:)` with a trait-based provider responds to `preferredColorScheme` at all in
/// this SwiftUI version, and whether `XCUIScreen.main.screenshot()` on this runner captures the
/// app's window or a cached compositor frame. The second is worth eliminating first, because the
/// same runner has already been shown not to honour `XCUIDevice.shared.appearance`.
///
/// ## What this gate costs
///
/// The App Store set's sixth frame is captured in **light**, and the listing may not claim a dark
/// mode until this is reachable (D-024, D-027).
enum AppearanceAvailability {

    /// Flip to `true` only alongside a green `AppearanceUITests`.
    static let isDarkModeReachable = false
}
