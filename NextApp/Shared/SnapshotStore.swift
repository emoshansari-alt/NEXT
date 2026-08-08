import Foundation
import NextKit

/// The one file the app and the widget both touch.
///
/// Compiled into **both** targets rather than shared through a framework: it is forty lines with
/// no state, and an embedded framework would cost launch time in an extension that is expected
/// to render in milliseconds.
///
/// It lives here rather than in `NextKit` because `containerURL(forSecurityApplicationGroupIdentifier:)`
/// is Darwin-only — referencing it there would break the Windows and Linux builds that make
/// Tier 1 possible at all.
struct SnapshotStore {

    /// Must match the App Group entitlement on both targets.
    static let appGroup = "group.com.nextapp.next"

    private static let filename = "recommendation.json"

    private let directory: URL?

    /// `nil` when the App Group container is unavailable, which is the honest state to be in:
    /// see `containerIsAvailable`.
    init(appGroup: String = SnapshotStore.appGroup) {
        directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        )
    }

    /// Whether the shared container resolved.
    ///
    /// Without it the app and the widget cannot see the same bytes, so the widget will show its
    /// placeholder forever. The app itself is unaffected — nothing else depends on this — which
    /// is exactly why it must be checked explicitly rather than inferred from things still
    /// appearing to work.
    var containerIsAvailable: Bool { directory != nil }

    private var fileURL: URL? {
        directory?.appendingPathComponent(filename)
    }

    /// Writes the snapshot. Silently does nothing if there is no shared container.
    ///
    /// Failing loudly here would put a storage error in front of a student because a *widget*
    /// could not be updated, which is not a problem they have or can solve.
    func write(_ snapshot: RecommendationSnapshot) {
        guard let fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }

        // Atomic: the widget can be woken to read this at any moment, and a half-written file
        // would decode as nothing at all.
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Reads the snapshot, or `nil` if there is none yet.
    func read() -> RecommendationSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(RecommendationSnapshot.self, from: data)
    }

    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
