import Foundation
import SwiftUI
import Testing

@testable import NextApp

/// Tier 2. The dark-mode setting.
///
/// Every colour in `NextPalette` has always declared both appearances, so dark *rendered* long
/// before this existed — what did not exist was a way to ask for it without changing the whole
/// phone. These cover the part that can be got wrong off-screen; `SettingsUITests` drives the
/// picker and measures the actual pixels, because a preference that is stored correctly and
/// never applied would pass everything here.
@Suite("Appearance — the choice")
struct AppearancePreferenceTests {

    private func store() -> AppSettingsStore {
        // A suite of its own per test, so one test's choice cannot leak into another's.
        let name = "next.appearance.tests.\(UUID().uuidString)"
        return AppSettingsStore(defaults: UserDefaults(suiteName: name) ?? .standard)
    }

    @Test("NEXT follows the phone until somebody says otherwise")
    func theDefaultIsToFollowTheSystem() {
        // The behaviour NEXT had before this setting existed, and the one most people never
        // think about. Adding a choice must not quietly change what happens to everyone who
        // never makes it.
        #expect(store().appearance == .system)
    }

    @Test("each choice survives being written and read back")
    func everyChoiceRoundTrips() {
        for choice in AppearancePreference.allCases {
            let settings = store()
            settings.appearance = choice

            #expect(settings.appearance == choice, "\(choice)")
        }
    }

    @Test("a value the app does not recognise falls back to following the phone")
    func anUnknownStoredValueIsSafe() {
        // Reordering the cases must never silently change somebody's choice, which is why this
        // is stored as a raw string. A value from a future version — or a corrupted one — lands
        // on the default rather than on whichever case happens to be first.
        let defaults = UserDefaults(suiteName: "next.appearance.tests.\(UUID().uuidString)")
        defaults?.set("solarized", forKey: "next.appearance")

        #expect(AppSettingsStore(defaults: defaults ?? .standard).appearance == .system)
    }

    @Test("only the system option leaves SwiftUI to decide")
    func onlySystemDeclinesToOverride() {
        // `nil` is what keeps "match my phone" working when the phone changes while NEXT is
        // open. Returning an explicit scheme there would pin the app to whatever it happened to
        // be at launch.
        #expect(AppearancePreference.system.colorScheme == nil)
        #expect(AppearancePreference.light.colorScheme == .light)
        #expect(AppearancePreference.dark.colorScheme == .dark)
    }

    @Test("choosing an appearance writes through immediately")
    func theChoiceIsPersistedAsItIsMade() async {
        // Not on dismiss. The user watches the whole app change colour the moment they tap, and
        // an app that visibly changed and then forgot after a relaunch is worse than one that
        // never offered.
        // Built and used entirely on the main actor, because `AppearanceState` is isolated to it
        // and `AppSettingsStore` is not `Sendable` — handing one across would be a data race the
        // compiler is right to refuse. Only the suite name crosses, which is a `String`.
        let name = "next.appearance.tests.\(UUID().uuidString)"
        await MainActor.run {
            let settings = AppSettingsStore(defaults: UserDefaults(suiteName: name) ?? .standard)
            AppearanceState(store: settings).preference = .dark
        }

        // Read back through a *different* store instance, which is what a relaunch does.
        let reread = AppSettingsStore(defaults: UserDefaults(suiteName: name) ?? .standard)

        #expect(reread.appearance == .dark)
    }

    @Test("every option is offered, and named in words rather than in jargon")
    func theOptionsReadPlainly() {
        #expect(AppearancePreference.allCases.count == 3)
        #expect(AppearancePreference.system.label == "Match my phone")
        #expect(AppearancePreference.light.label == "Light")
        #expect(AppearancePreference.dark.label == "Dark")
    }
}
