import Foundation

/// What the widget shows, as a few hundred bytes the app writes and the widget reads.
///
/// The widget deliberately does **not** open the task store. Widget extensions run under a hard
/// memory limit and are launched by the system at unpredictable moments; standing up SwiftData,
/// its schema and a migration plan to render two lines of text would be both slow and fragile.
/// A snapshot moves all of that work into the app, where it has already happened anyway.
///
/// It carries rendered strings rather than a `Recommendation`. Copy lives in the app layer, and
/// a widget re-deriving its own wording from raw data is how the two end up disagreeing.
public struct RecommendationSnapshot: Hashable, Sendable, Codable {

    /// How old a snapshot may be before the widget should stop presenting it as current.
    ///
    /// A day. Beyond that the recommendation was computed against deadlines that have since
    /// moved, and a widget showing it is not showing the recommendation — it is showing history,
    /// and the user cannot tell the difference.
    public static let stalenessHorizon: TimeInterval = 24 * 3600

    public let generatedAt: Date

    /// The task the headline belongs to, or `nil` when there is nothing to do.
    public let taskID: TaskID?

    /// The parent task's name, shown above the action when it adds context.
    public let taskTitle: String?

    /// The line the widget leads with: the action to take, or the empty-state headline.
    public let headline: String

    /// "Due tomorrow · ~15 min", or the empty-state detail. Optional because not every task
    /// knows anything worth adding.
    public let detail: String?

    public init(
        generatedAt: Date,
        taskID: TaskID?,
        taskTitle: String?,
        headline: String,
        detail: String?
    ) {
        self.generatedAt = generatedAt
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.headline = headline
        self.detail = detail
    }

    /// A snapshot for when there is nothing to recommend.
    public static func nothingToDo(
        generatedAt: Date,
        headline: String,
        detail: String?
    ) -> RecommendationSnapshot {
        RecommendationSnapshot(
            generatedAt: generatedAt,
            taskID: nil,
            taskTitle: nil,
            headline: headline,
            detail: detail
        )
    }

    public var hasWork: Bool { taskID != nil }

    /// Whether this is too old to present as the current answer.
    ///
    /// A snapshot dated in the future is *not* stale. That is reachable from a clock change or
    /// a time-zone move, and blanking the widget for a reason the user can neither see nor fix
    /// would be worse than showing something slightly off.
    public func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(generatedAt) > Self.stalenessHorizon
    }

    /// Where tapping the widget should land.
    public var deepLink: URL? {
        guard let taskID else { return DeepLink.today.url }
        return DeepLink.task(taskID).url
    }
}

/// Somewhere in the app a URL can point.
///
/// Kept in `NextKit` so the widget, the notification handler and the app all parse links the
/// same way. Three places inventing their own URL format is three chances to disagree.
public enum DeepLink: Hashable, Sendable {

    case today
    case task(TaskID)

    public static let scheme = "next"

    public var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme

        switch self {
        case .today:
            components.host = "today"
        case .task(let id):
            components.host = "task"
            // Percent-encoded by URLComponents. Identifiers are UUID strings in production, but
            // `TaskID` does not promise that, and a link that silently fails to parse opens
            // nothing at all.
            components.path = "/" + id.rawValue
        }

        return components.url
    }

    /// Parses a URL, or returns `nil` if it is not one of ours.
    ///
    /// Unrecognised links are rejected rather than guessed at. Opening the wrong task because a
    /// URL nearly matched would be worse than ignoring it.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.scheme
        else { return nil }

        switch components.host {
        case "today":
            self = .today

        case "task":
            let identifier = String(components.path.dropFirst())
            guard !identifier.isEmpty else { return nil }
            self = .task(TaskID(identifier))

        default:
            return nil
        }
    }
}
