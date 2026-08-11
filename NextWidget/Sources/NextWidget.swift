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
                // The widget *is* the card — the same stock, the same spine, the same eyebrow.
                // On a home screen the card is what makes NEXT recognisable at a glance.
                .containerBackground(NextPalette.card, for: .widget)
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
                .nextEyebrow()
                .accessibilityHidden(true)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .leading) {
            // The card's ballpoint spine, carried onto the home screen.
            Rectangle()
                .fill(NextPalette.biro)
                .frame(width: 3)
                .offset(x: -12)
        }
        .widgetURL(link)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot, !snapshot.isStale(at: entry.date) {
            VStack(alignment: .leading, spacing: 4) {
                if let title = snapshot.taskTitle {
                    Text(title)
                        .font(NextType.meta)
                        .foregroundStyle(NextPalette.inkSecondary)
                        .lineLimit(1)
                }

                Text(snapshot.headline)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(NextPalette.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)

                if let detail = snapshot.detail {
                    Text(detail)
                        .font(NextType.meta)
                        .foregroundStyle(NextPalette.inkSecondary)
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
                .font(NextType.parent)
                .foregroundStyle(NextPalette.inkSecondary)
                .accessibilityIdentifier("widget-placeholder")
        }
    }

    /// Where a tap lands. The rule is `RecommendationSnapshot`'s, so it is testable at Tier 1 and
    /// cannot disagree with the staleness the view above uses to decide what to draw.
    private var link: URL? {
        entry.snapshot?.link(at: entry.date) ?? DeepLink.today.url
    }
}
