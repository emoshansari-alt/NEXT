import SwiftUI
import UIKit

/// Applies the chosen appearance to every window, not just to SwiftUI's environment.
///
/// ## Why the window and not only `preferredColorScheme`
///
/// Every colour in `NextPalette` is a `UIColor` with a trait-based provider — chosen deliberately,
/// so one definition serves the app, the widget and `resolvedColor(with:)` in a test.
/// `preferredColorScheme` sets SwiftUI's `colorScheme` but does not change a window's
/// `UITraitCollection`, so UIKit-backed containers keep resolving the old style. The failure is
/// not "dark mode does nothing"; it is worse — **half the screen switches**, and the accessibility
/// audit reported `inkSecondary` failing contrast on Today, which is what light ink on a light
/// desk looks like.
///
/// ## Why this asks the scene rather than a view
///
/// The first attempt was a `UIViewRepresentable` that set `view.window?.overrideUserInterfaceStyle`.
/// It never fired: the view was zero-sized and hidden, so it was never attached to a window and
/// `view.window` was always `nil`. Two CI rounds measured the identical brightness — 0.8067, to
/// the digit — which is what "the code never ran" looks like when a test only checks the outcome.
///
/// Asking `UIApplication` for its connected scenes needs no view in the hierarchy, no layout pass
/// and no attachment. It is the one lookup that cannot silently do nothing.
enum WindowAppearance {

    // Main-actor isolated: `UIApplication.shared`, `connectedScenes`, `windows` and
    // `overrideUserInterfaceStyle` all are. Debug only warned about this; the Release step's
    // `SWIFT_TREAT_WARNINGS_AS_ERRORS` is what turned it into a failure, which is the whole
    // reason that step exists.
    @MainActor
    static func apply(_ preference: AppearancePreference) {
        let style: UIUserInterfaceStyle = preference == .dark ? .dark : .light

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

extension View {

    /// Pins the whole app to one appearance, in both SwiftUI's and UIKit's terms.
    ///
    /// Applied on appear *and* on every change: on appear because the first launch has to be
    /// right before anything is drawn, and on change because the switch is three levels down in
    /// a sheet and the window will not hear about it otherwise.
    ///
    /// Both halves are load-bearing and `AppearanceUITests` measures both. `preferredColorScheme`
    /// is what makes the very first frame right, before any task has run; the window override is
    /// what makes UIKit-backed containers agree, and the probe reports `window=dark` alongside
    /// `scheme=dark` on a screen measured at 0.119 brightness.
    func appearance(_ preference: AppearancePreference) -> some View {
        preferredColorScheme(preference.colorScheme)
            .task(id: preference) { WindowAppearance.apply(preference) }
    }
}
