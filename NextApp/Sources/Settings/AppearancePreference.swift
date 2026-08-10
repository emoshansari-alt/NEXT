import SwiftUI

/// Light or dark. Light is the default.
///
/// An earlier version offered a third option — follow the phone — and the owner cut it. Two
/// states is the smaller decision (P1) and the one people already understand from every other
/// app: a switch labelled Dark mode, off by default.
///
/// The cost is stated rather than hidden: NEXT no longer follows the system appearance, so
/// somebody whose phone is dark still opens NEXT in light until they turn this on. That is the
/// trade a two-state switch makes, and it is the right one here — the feature exists because
/// people's eyes hurt, and "go and change your phone" was never an acceptable answer to that.
///
/// Dark has always *rendered*: every colour in `NextPalette` declares both appearances, and
/// `NextPaletteTests` holds each pair to 4.5:1 in both. What did not exist was a way to ask.
enum AppearancePreference: String, CaseIterable, Codable, Sendable {

    case light
    case dark

    /// What SwiftUI is told at the scene root. Always explicit, because with no follow-the-phone
    /// option there is nothing to defer to.
    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }

    var isDark: Bool { self == .dark }

    static func from(isDark: Bool) -> AppearancePreference { isDark ? .dark : .light }
}
