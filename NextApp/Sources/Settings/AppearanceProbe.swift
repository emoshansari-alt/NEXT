import SwiftUI
import UIKit

/// A test-only readout of every link between the user's choice and the pixels.
///
/// Four rounds of measuring brightness proved that flipping the switch changed nothing, and could
/// not say *which* step failed — the write, the re-render, SwiftUI's environment, the window's
/// trait collection, or the palette's own resolution. Each of those is a separate mechanism and
/// each can fail alone. This reports all five in one accessibility label, so a failing run names
/// the broken link instead of only its outcome.
///
/// **It is not the proof, and must never be mistaken for it.** Every value here is something the
/// app says about itself, and a wrong appearance that is confidently self-reported is exactly the
/// failure that produced a green dark-mode audit running in light. The proof is the pixels, in
/// `AppearanceUITests`. This is what tells you where to look when they disagree.
///
/// Present only under `-ui-testing` together with `-ui-appearance-probe`, so it cannot reach a
/// user and cannot enter the accessibility audit's element tree on any screen that audits.
@MainActor
struct AppearanceProbe: View {

    static let argument = "-ui-appearance-probe"

    static let isEnabled: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(NEXTApp.uiTestingArgument) && arguments.contains(argument)
    }()

    /// Passed in rather than read here, so this reports what **`RootView`'s own body** saw. A
    /// probe that read the observable itself could re-render while the root did not, and would
    /// then report a change that never reached the screen.
    let preference: AppearancePreference?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    var body: some View {
        // Laid out but invisible, and in an overlay so it displaces nothing. `.hidden()` and a
        // zero frame both remove an element from the accessibility tree, which is the one thing
        // this cannot afford.
        Text(report)
            .font(.system(size: 2))
            .lineLimit(1)
            .foregroundStyle(.clear)
            .allowsHitTesting(false)
            .accessibilityIdentifier("appearance-probe")
    }

    private var report: String {
        [
            "pref=\(preference?.rawValue ?? "none")",
            "scheme=\(colorScheme == .dark ? "dark" : "light")",
            "window=\(Self.name(keyWindowStyle))",
            "trait=\(Self.name(UITraitCollection.current.userInterfaceStyle))",
            "desk=\(hex(NextPalette.desk))",
            "card=\(hex(NextPalette.card))",
            "ink=\(hex(NextPalette.ink))",
            // The dark audit fails on exactly two elements and both are `inkSecondary` on the
            // card, where the values clear 6.5:1. Either it resolves to the light value while
            // the card resolves to the dark one — the half-switched signature — or the audit is
            // measuring something the palette does not describe. These two together say which.
            "inkSecondary=\(hex(NextPalette.inkSecondary))"
        ].joined(separator: " ")
    }

    /// What SwiftUI will actually paint, resolved through this view's environment.
    ///
    /// The load-bearing measurement of the six. `NextPalette` is built from `UIColor` trait
    /// providers, so it answers to a `UITraitCollection` rather than to SwiftUI's `colorScheme`.
    /// If `scheme` says dark and this still returns the light value, the palette is the broken
    /// link and no amount of setting `preferredColorScheme` will move it.
    private func hex(_ color: Color) -> String {
        let resolved = color.resolve(in: environment)
        let channel = { (value: Float) in Int((max(0, min(1, value)) * 255).rounded()) }
        return String(
            format: "%02X%02X%02X",
            channel(resolved.red), channel(resolved.green), channel(resolved.blue)
        )
    }

    private var keyWindowStyle: UIUserInterfaceStyle {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                return window.overrideUserInterfaceStyle
            }
        }
        return .unspecified
    }

    private static func name(_ style: UIUserInterfaceStyle) -> String {
        switch style {
        case .dark: "dark"
        case .light: "light"
        default: "unspecified"
        }
    }
}
