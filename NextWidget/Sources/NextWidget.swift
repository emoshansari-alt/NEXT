import NextKit
import SwiftUI
import WidgetKit

/// The NEXT widget: the recommendation, on the home screen.
///
/// It reads a snapshot the app wrote and renders it. It does not open the task store, does not
/// run the ranking engine, and makes no decisions — widget extensions have a hard memory limit
/// and are woken at unpredictable moments, so all of that work stays in the app where it has
/// already happened.
@main
struct NextWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextWidget()
    }
}

struct NextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextRecommendation", provider: SnapshotProvider()) { entry in
            NextWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("NEXT")
        .description("The one thing to start.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: RecommendationSnapshot?
}

struct SnapshotProvider: TimelineProvider {

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: SnapshotStore().read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let entry = SnapshotEntry(date: now, snapshot: SnapshotStore().read())

        // One entry, refreshed in an hour. There is nothing here that changes on its own — the
        // content only changes when the app rewrites the snapshot, and the app reloads timelines
        // when it does. The hourly refresh exists solely so a snapshot can go stale and stop
        // claiming to be current; scheduling anything tighter would spend the user's battery
        // re-rendering identical text.
        let next = now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - View

struct NextWidgetView: View {

    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEXT")
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(link)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot, !snapshot.isStale(at: entry.date) {
            VStack(alignment: .leading, spacing: 4) {
                if let title = snapshot.taskTitle {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(snapshot.headline)
                    .font(.headline)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)

                if let detail = snapshot.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                [snapshot.taskTitle, snapshot.headline, snapshot.detail]
                    .compactMap { $0 }
                    .joined(separator: ". ")
            )
        } else {
            // Covers a first install, a stale snapshot, and an unavailable shared container.
            // All three mean the same thing to the reader — the widget does not know — and
            // saying so is better than showing a recommendation that may no longer be true.
            Text("Open NEXT to see what is next.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("widget-placeholder")
        }
    }

    private var link: URL? {
        guard let snapshot = entry.snapshot, !snapshot.isStale(at: entry.date) else {
            return DeepLink.today.url
        }
        return snapshot.deepLink
    }
}
