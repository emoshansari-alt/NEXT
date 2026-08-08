import Foundation
import NextKit

/// Seed data for the first run, and for SwiftUI previews and UI tests.
///
/// This exists because persistence and capture are not built yet. It is replaced by the real
/// `TaskRepository` in Phase 2, and is not intended to ship: a real first run shows the empty
/// state and invites the user to add something.
enum SampleTasks {

    static var starter: [TaskItem] {
        let now = Date()
        let calendar = Calendar.current

        func inDays(_ days: Int, hour: Int = 17) -> Date? {
            guard let day = calendar.date(byAdding: .day, value: days, to: now) else { return nil }
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
        }

        return [
            TaskItem(
                id: TaskID("sample-history"),
                title: "History essay",
                createdAt: now,
                deadline: inDays(3),
                importance: .important,
                estimatedMinutes: 20,
                nextAction: "Find three sources."
            ),
            TaskItem(
                id: TaskID("sample-chemistry"),
                title: "Chemistry worksheet",
                createdAt: now,
                deadline: inDays(1),
                estimatedMinutes: 15,
                nextAction: "Do questions 1 to 5."
            ),
            TaskItem(
                id: TaskID("sample-email"),
                title: "Email Professor Adeyemi",
                createdAt: now,
                estimatedMinutes: 5,
                nextAction: "Ask about the extension."
            )
        ]
    }
}
