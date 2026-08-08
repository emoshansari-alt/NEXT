import Foundation
import NextKit
import WidgetKit

/// Keeps the widget's snapshot in step with what Today shows.
///
/// The app owns every decision; this only renders the current one into the shared container and
/// tells WidgetKit to redraw. The copy here is the same copy Today uses, so the two cannot end
/// up describing the same recommendation differently.
struct SnapshotPublisher {

    private let store: SnapshotStore
    private let reloadTimelines: () -> Void

    init(
        store: SnapshotStore = SnapshotStore(),
        reloadTimelines: @escaping () -> Void = {
            WidgetCenter.shared.reloadAllTimelines()
        }
    ) {
        self.store = store
        self.reloadTimelines = reloadTimelines
    }

    /// Writes the current outcome and asks the widget to redraw.
    func publish(_ outcome: RecommendationOutcome, at now: Date) {
        store.write(Self.snapshot(for: outcome, at: now))
        reloadTimelines()
    }

    /// Builds the snapshot. Separated from writing so it can be tested without a container.
    static func snapshot(
        for outcome: RecommendationOutcome,
        at now: Date
    ) -> RecommendationSnapshot {
        switch outcome {
        case .recommended(let recommendation):
            return RecommendationSnapshot(
                generatedAt: now,
                taskID: recommendation.task.id,
                // Shown above the action only when it says something the action does not.
                taskTitle: recommendation.task.title == recommendation.actionText
                    ? nil
                    : recommendation.task.title,
                headline: recommendation.actionText,
                detail: detail(for: recommendation)
            )

        case .nothingToDo:
            return .nothingToDo(
                generatedAt: now,
                headline: UnavailabilityCopy.emptyHeadline,
                detail: UnavailabilityCopy.emptyDetail
            )

        case .nothingAvailable(let reason):
            return .nothingToDo(
                generatedAt: now,
                headline: UnavailabilityCopy.headline(for: reason),
                detail: UnavailabilityCopy.detail(for: reason)
            )
        }
    }

    private static func detail(for recommendation: Recommendation) -> String? {
        var parts: [String] = []

        if recommendation.task.deadline != nil {
            parts.append(
                recommendation.explanation.sentence.replacingOccurrences(of: ".", with: "")
            )
        }
        if let minutes = recommendation.task.estimatedMinutes {
            parts.append("~\(minutes) min")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
