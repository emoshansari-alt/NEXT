import SwiftUI

/// Whether NEXT follows the system's appearance or is pinned to one.
///
/// ## Why three options and not a Dark Mode switch
///
/// The request was a toggle, and a toggle would have been the wrong shape by one option. NEXT
/// has always followed the system, which is the right default and the one most people never
/// think about — a two-state switch has to either replace that behaviour or bolt a third state
/// onto an "off" position that then means two different things. Three named choices cost the
/// same single decision (P1) and keep "follow my phone" reachable.
///
/// It is the same shape as the reminder pickers a few rows above it in Settings, so it adds a
/// row rather than a new idea.
///
/// ## Why this is worth building rather than leaving to the system
///
/// Every colour in `NextPalette` already declares both appearances, so dark has always
/// *rendered*; what did not exist was a way to ask for it. Someone whose eyes hurt in a bright
/// app should not have to change their whole phone to read a task, and someone who keeps their
/// phone light all day should still be able to put NEXT in dark at midnight — which, given what
/// this app is for, is exactly when it gets opened.
enum AppearancePreference: String, CaseIterable, Codable, Sendable {

    /// Follow the phone. The default, and what NEXT did before this existed.
    case system

    case light
    case dark

    /// What SwiftUI should be told. `nil` means "do not override", which is how the system
    /// option keeps working when the user changes their phone's setting while NEXT is open.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The label in Settings. Sentence case, like every other control in the app.
    var label: String {
        switch self {
        case .system: "Match my phone"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
