import Foundation
import NextKit

/// Where the user's choices live.
///
/// `UserDefaults` rather than the task store: these are preferences about the app, not the
/// user's work. They should not travel inside a task database or complicate a schema migration.
struct AppSettingsStore {

    private enum Key {
        static let reminders = "next.reminderPreferences"
        static let cloudIntelligence = "next.cloudIntelligenceConsented"
        static let appearance = "next.appearance"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var reminderPreferences: ReminderPreferences {
        get {
            guard let data = defaults.data(forKey: Key.reminders),
                  let decoded = try? JSONDecoder().decode(ReminderPreferences.self, from: data)
            else {
                // Unreadable preferences fall back to the defaults rather than throwing. A
                // setting nobody can decode is worth losing; the app is not.
                return .default
            }
            return decoded
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.reminders)
        }
    }

    /// Whether the user has agreed to task text leaving the device for AI processing.
    ///
    /// **Defaults to false and must stay that way.** `PRIVACY.md` promises explicit, informed,
    /// revocable consent before any task text is sent anywhere, and a default of `true` would
    /// make that promise false the moment a cloud provider exists.
    ///
    /// Nothing consults this yet because the only provider is the offline template one, which
    /// sends nothing. The switch exists first so that a cloud provider cannot be added without
    /// a consent gate already standing in front of it.
    var cloudIntelligenceConsented: Bool {
        get { defaults.bool(forKey: Key.cloudIntelligence) }
        nonmutating set { defaults.set(newValue, forKey: Key.cloudIntelligence) }
    }

    /// Light, dark, or whatever the phone is doing.
    ///
    /// Stored as the raw string rather than an index, so reordering the cases cannot silently
    /// change what somebody chose. An unreadable or unknown value falls back to `.system`, which
    /// is both the default and the least surprising thing to land on.
    var appearance: AppearancePreference {
        get {
            guard let raw = defaults.string(forKey: Key.appearance),
                  let value = AppearancePreference(rawValue: raw)
            else { return .system }
            return value
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }
}
