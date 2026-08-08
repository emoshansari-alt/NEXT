import Foundation
import NextKit

/// Seed data for a first run, and for SwiftUI previews and UI tests.
///
/// **Temporary.** Capture does not exist yet, so an empty first run would be a dead end — no way
/// to add anything and nothing to do. This goes when Phase 5 lands and a real first run shows
/// the empty state and invites the user to write down what is on their mind.
///
/// Takes `now` rather than reading the clock so the seeded deadlines are relative to whatever
/// instant the caller is working at, including a fixed one in tests.
enum SampleTasks {

    static func starter(now: Date) -> [TaskItem] {
        let calendar = Calendar.current

        func evening(inDays days: Int) -> Date? {
            guard let day = calendar.date(byAdding: .day, value: days, to: now) else { return nil }
            return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day)
        }

        return [
            TaskItem(
                id: TaskID("sample-history"),
                title: "History essay",
                createdAt: now,
                deadline: evening(inDays: 3),
                importance: .important,
                estimatedMinutes: 20,
                nextAction: "Find three sources."
            ),
            TaskItem(
                id: TaskID("sample-chemistry"),
                title: "Chemistry worksheet",
                createdAt: now.addingTimeInterval(1),
                deadline: evening(inDays: 1),
                estimatedMinutes: 15,
                nextAction: "Do questions 1 to 5."
            ),
            TaskItem(
                id: TaskID("sample-email"),
                title: "Email Professor Adeyemi",
                createdAt: now.addingTimeInterval(2),
                estimatedMinutes: 5,
                nextAction: "Ask about the extension."
            )
        ]
    }
}
