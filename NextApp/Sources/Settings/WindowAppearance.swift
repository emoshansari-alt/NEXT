import SwiftUI
import UIKit

/// Applies the chosen appearance to the **window**, not just to SwiftUI's environment.
///
/// `preferredColorScheme` alone is not enough here, and the accessibility audit is what proved
/// it. Every colour in `NextPalette` is a `UIColor` with a trait-based provider — chosen
/// deliberately, so one definition serves the app, the widget and `resolvedColor(with:)` in a
/// test. `preferredColorScheme` sets SwiftUI's `colorScheme` but does not change the window's
/// `UITraitCollection`, so UIKit-backed containers keep resolving the old style. The result is
/// not "dark mode does not work"; it is worse — **half the screen switches**. The audit reported
/// `inkSecondary` text failing contrast on Today, which is exactly what light-grey ink on a light
/// desk looks like, and the screen measured 0.81 brightness while claiming to be dark.
///
/// Overriding the window makes UIKit and SwiftUI agree on one answer, which is the only state
/// where a palette built from trait providers is coherent.
struct WindowAppearance: UIViewRepresentable {

    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> UIView {
        // A zero-size, non-interactive view whose only job is to find the window it is in.
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        // Deferred, because on the first pass the view is not in a window yet. Re-applied on
        // every update so a change while the app is running lands too.
        DispatchQueue.main.async {
            view.window?.overrideUserInterfaceStyle = style
        }
    }
}

extension View {

    /// Pins the whole app to one appearance, in both SwiftUI's and UIKit's terms.
    func appearance(_ preference: AppearancePreference) -> some View {
        preferredColorScheme(preference.colorScheme)
            .background(
                WindowAppearance(style: preference == .dark ? .dark : .light)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            )
    }
}
