import Foundation
import Testing

@testable import NextKit
import NextKitTestSupport

// MARK: - Deterministic dates
//
// Every test in this suite pins "now" to a fixed instant. NextKit is forbidden from reading
// the clock itself (DECISIONS.md D-007), so tests are fully reproducible and deadline edge
// cases can be expressed exactly.

/// Parses an ISO-8601 instant, e.g. `iso("2026-03-10T09:00:00Z")`.
/// Traps on a malformed literal — that is a mistake in the test, not a runtime condition.
func iso(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: string) else {
        fatalError("Malformed test date literal: \(string)")
    }
    return date
}

extension Date {
    /// The instant every test treats as "now": Tuesday 10 March 2026, 09:00 UTC.
    /// Mid-week and mid-morning, so that "tomorrow", "this weekend" and "overdue"
    /// are all expressible without wrapping past a month or year boundary.
    static let testReference = iso("2026-03-10T09:00:00Z")

    /// `Date.testReference` shifted by a whole number of hours. Negative means the past.
    static func hoursFromReference(_ hours: Double) -> Date {
        testReference.addingTimeInterval(hours * 3600)
    }

    /// `Date.testReference` shifted by a whole number of days. Negative means the past.
    static func daysFromReference(_ days: Double) -> Date {
        hoursFromReference(days * 24)
    }
}

// MARK: - Builders

/// Builds a `TaskItem` with sensible defaults so each test only states what it cares about.
func makeTask(
    id: String,
    title: String = "Untitled",
    status: TaskStatus = .active,
    deadline: Date? = nil,
    importance: Importance = .normal,
    estimatedMinutes: Int? = nil,
    nextAction: String? = nil,
    prerequisiteIDs: [TaskID] = [],
    parentID: TaskID? = nil,
    rejections: [Rejection] = [],
    rejectionsSupersededAt: Date? = nil,
    createdAt: Date = .testReference,
    updatedAt: Date? = nil,
    completedAt: Date? = nil
) -> TaskItem {
    TaskItem(
        id: TaskID(id),
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        status: status,
        completedAt: completedAt,
        deadline: deadline,
        importance: importance,
        estimatedMinutes: estimatedMinutes,
        nextAction: nextAction,
        prerequisiteIDs: prerequisiteIDs,
        parentID: parentID,
        rejections: rejections,
        rejectionsSupersededAt: rejectionsSupersededAt
    )
}

/// A rejection that happened a given number of hours before `Date.testReference`.
func rejection(_ reason: RejectionReason = .cantRightNow, hoursAgo: Double) -> Rejection {
    Rejection(reason: reason, at: .hoursFromReference(-hoursAgo))
}

// The TaskRepository contract used to live here. It now lives in the NextKitTestSupport
// library (Sources/NextKitTestSupport/RepositoryContract.swift) so that NextApp's Tier 2 test
// target can run the identical checks against the SwiftData store. A contract only the
// in-memory implementation could execute was a description of one implementation, not a
// contract. `verifyRepositoryContract(_:)` is re-exported by the import above.
