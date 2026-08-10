import Observation
import SwiftUI

/// The chosen appearance, shared by the one place that sets it and the one place that applies it.
///
/// Settings is a sheet several levels below the scene root, and `preferredColorScheme` only means
/// anything at the root — so the choice cannot simply live in `SettingsViewModel`. This is the
/// smallest thing that connects them: one observable value, owned by `NEXTApp`, written by the
/// picker and read by the root.
///
/// Writing through to `AppSettingsStore` on every change rather than on dismiss is deliberate.
/// The user sees the whole app change colour the instant they tap, and an app that visibly
/// changed and then forgot after a relaunch would be worse than one that never offered.
@MainActor
@Observable
final class AppearanceState {

    var preference: AppearancePreference {
        didSet { store.appearance = preference }
    }

    private let store: AppSettingsStore

    init(store: AppSettingsStore = AppSettingsStore()) {
        self.store = store
        // Assigned in `init`, so `didSet` does not fire and the load does not immediately
        // rewrite what it just read.
        preference = store.appearance
    }
}
