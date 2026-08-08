import Foundation

/// The answer to "Why this?".
///
/// Structured rather than a bare string for two reasons: it can be localised or reworded in
/// the app layer without touching the engine, and it can be asserted on in tests without
/// pinning exact copy. `sentence` gives a deterministic English default so the feature works
/// offline with no model and no app-layer work (PRODUCT_SPEC.md §4.4).
public enum ExplanationReason: Hashable, Sendable {

    /// The deadline has already passed, by this much.
    case overdue(by: TimeInterval)

    /// The deadline is this far away.
    case dueSoon(within: TimeInterval)

    /// Finishing it unblocks this many other outstanding tasks.
    case unlocksOtherWork(count: Int)

    /// The user marked it Important.
    case markedImportant

    /// It fits the time budget the user stated, which is this many minutes.
    case fitsTheTimeYouHave(minutes: Int)

    /// There is a concrete first step recorded, so there is nothing to decide before starting.
    case hasAClearFirstStep

    /// Nothing distinguishes it — but something still has to be offered, and saying so plainly
    /// beats a blank "Why this?".
    case nothingElsePending

    /// A short, deterministic English rendering.
    ///
    /// Kept calm and factual on purpose. NEXT is a competent tool, not a motivational speaker
    /// (PRODUCT_SPEC.md §3), and no sentence here may imply the user has fallen short.
    public var sentence: String {
        switch self {
        case .overdue(let interval):
            "Overdue by \(Self.humanised(interval))."

        case .dueSoon(let interval):
            "Due in \(Self.humanised(interval))."

        case .unlocksOtherWork(let count):
            "Finishing this unblocks \(count) other task\(count == 1 ? "" : "s")."

        case .markedImportant:
            "You marked this important."

        case .fitsTheTimeYouHave(let minutes):
            "Fits the \(minutes) minutes you have."

        case .hasAClearFirstStep:
            "There is a clear first step."

        case .nothingElsePending:
            "Nothing else is more pressing right now."
        }
    }

    /// Renders a duration at the coarsest unit that still reads naturally.
    ///
    /// Deliberately not `DateComponentsFormatter`: its output varies with locale and platform,
    /// which would make these strings untestable and inconsistent between the Windows and
    /// macOS test runs.
    static func humanised(_ interval: TimeInterval) -> String {
        let seconds = max(0, interval)

        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }

        let hours = Int((seconds / 3600).rounded())
        if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }

        let days = Int((seconds / 86_400).rounded())
        return "\(days) day\(days == 1 ? "" : "s")"
    }
}
