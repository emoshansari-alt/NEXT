import SwiftUI

/// NEXT's colours, and the only place any of them are written down.
///
/// The direction is **Index Card** (DECISIONS.md D-023): one card resting on a desk. The accent is
/// ballpoint blue because that is the colour of a student's own handwriting, and the marker is a
/// highlighter — used as a *stripe*, never behind text, so it can never become a contrast problem.
///
/// Every colour is declared for both appearances at the point of definition rather than in an
/// asset catalogue, for the same reason `project.yml` is a file rather than an Xcode project: a
/// value in source can be read, reviewed and tested from the development machine. `NextPaletteTests`
/// resolves each pair and asserts the contrast ratio, so the palette cannot drift below 4.5:1
/// without a test failing.
enum NextPalette {

    /// The surface the card rests on. Never holds text.
    static let desk = dynamic(light: 0xDAD6CD, dark: 0x101114)

    /// The card itself. Everything readable sits on this.
    static let card = dynamic(light: 0xFDFCFA, dark: 0x1E2024)

    /// Primary text.
    static let ink = dynamic(light: 0x1C1A17, dark: 0xF2F1EE)

    /// Supporting text — the parent task, the meta line, anything secondary.
    ///
    /// Chosen to clear 4.5:1 on `card` in both appearances, which the system's own `.secondary`
    /// does not reliably do at caption sizes. That was one of the audit's findings.
    static let inkSecondary = dynamic(light: 0x5C584F, dark: 0xA8A69F)

    /// Ballpoint blue. The single accent: the card's spine, the primary action, the live mark.
    static let biro = dynamic(light: 0x2438C8, dark: 0x8FA0FF)

    /// Text placed *on* `biro`.
    static let onBiro = dynamic(light: 0xFFFFFF, dark: 0x0E0F13)

    /// Highlighter. A stripe or an underline, never a fill behind text.
    static let marker = dynamic(light: 0xE0A800, dark: 0xD8A93A)

    /// Hairlines and the card's own edge.
    static let edge = dynamic(light: 0xD8D3C9, dark: 0x33363C)

    /// Where something has gone wrong. Distinct from `biro` so a warning never reads as an action.
    static let warning = dynamic(light: 0x9A3412, dark: 0xF2A88A)

    // MARK: - Building one

    /// Both appearances, declared together.
    ///
    /// A `UIColor` with a dynamic provider rather than two `Color`s chosen by an environment read:
    /// this resolves correctly inside UIKit-backed containers, in the widget, and — the reason it
    /// matters here — under `resolvedColor(with:)` in a test.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
            }
        )
    }
}

extension UIColor {

    /// `0xRRGGBB`. Not a general-purpose parser — it takes an integer literal precisely so a
    /// malformed colour is a compile error rather than a silently black one at runtime.
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// WCAG relative luminance.
    var relativeLuminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)

        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// WCAG contrast ratio against another colour, from 1 (identical) to 21 (black on white).
    func contrastRatio(against other: UIColor) -> CGFloat {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
