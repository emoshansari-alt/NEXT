import Foundation
import NextKit
import SwiftData

/// How a `TaskItem` is written to disk.
///
/// A separate type from the domain model on purpose (DECISIONS.md D-006). `TaskItem` is a value
/// type in a module that cannot import SwiftData; this is a reference type that exists only to
/// be stored. Everything crosses between them at this boundary and nowhere else, which is what
/// keeps the whole domain layer testable on a machine with no Xcode — and what would make a
/// move to Core Data a change to one file rather than to the app.
///
/// ## Why enums and identifiers are stored as strings
///
/// `statusRaw` and `importanceRaw` are `String`, not the enums themselves. `#Predicate` over a
/// stored enum is fragile, and a status query is the single most common read in the app. The
/// raw values are the enums' own `rawValue`s, so the mapping cannot drift.
///
/// ## Why rejections are stored as JSON
///
/// `rejections` is a small append-only list that is never queried or sorted on — it is read
/// whole or not at all. Modelling it as a related entity would buy query power nobody needs and
/// cost a relationship, a delete rule, and a second table. A JSON blob is explicit, migrates
/// with an ordinary decoder, and keeps the row self-contained.
@Model
final class StoredTask {

    /// The domain `TaskID`'s raw value. Unique so a second write with the same identity
    /// replaces rather than duplicates.
    @Attribute(.unique) var identifier: String

    var title: String
    var createdAt: Date
    var updatedAt: Date

    var statusRaw: String
    var completedAt: Date?

    var deadline: Date?
    var importanceRaw: String
    var estimatedMinutes: Int?
    var nextAction: String?

    var prerequisiteIdentifiers: [String]
    var parentIdentifier: String?

    var rejectionsData: Data
    var rejectionsSupersededAt: Date?

    init(task: TaskItem) {
        identifier = task.id.rawValue
        title = task.title
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        statusRaw = task.status.rawValue
        completedAt = task.completedAt
        deadline = task.deadline
        importanceRaw = task.importance.rawValue
        estimatedMinutes = task.estimatedMinutes
        nextAction = task.nextAction
        prerequisiteIdentifiers = task.prerequisiteIDs.map(\.rawValue)
        parentIdentifier = task.parentID?.rawValue
        rejectionsData = Self.encode(task.rejections)
        rejectionsSupersededAt = task.rejectionsSupersededAt
    }

    /// Overwrites this row with a task. Identity is never rewritten — a row is one task for life.
    func apply(_ task: TaskItem) {
        title = task.title
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        statusRaw = task.status.rawValue
        completedAt = task.completedAt
        deadline = task.deadline
        importanceRaw = task.importance.rawValue
        estimatedMinutes = task.estimatedMinutes
        nextAction = task.nextAction
        prerequisiteIdentifiers = task.prerequisiteIDs.map(\.rawValue)
        parentIdentifier = task.parentID?.rawValue
        rejectionsData = Self.encode(task.rejections)
        rejectionsSupersededAt = task.rejectionsSupersededAt
    }

    /// Reads the row back as a domain value.
    ///
    /// **Decoding is deliberately lenient, and only ever in the direction of keeping the user's
    /// work.** An unrecognised status becomes `.active` and an unreadable rejection blob becomes
    /// an empty list, rather than either failing the read. The task itself is the thing the
    /// student wrote down; a status the app no longer understands, or tuning data it cannot
    /// parse, is not worth losing it over. Nothing here can invent a task, change its title, or
    /// move a deadline — the lenience only ever costs metadata.
    var domainValue: TaskItem {
        TaskItem(
            id: TaskID(identifier),
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: TaskStatus(rawValue: statusRaw) ?? .active,
            completedAt: completedAt,
            deadline: deadline,
            importance: Importance(rawValue: importanceRaw) ?? .normal,
            estimatedMinutes: estimatedMinutes,
            nextAction: nextAction,
            prerequisiteIDs: prerequisiteIdentifiers.map(TaskID.init),
            parentID: parentIdentifier.map(TaskID.init),
            rejections: Self.decode(rejectionsData),
            rejectionsSupersededAt: rejectionsSupersededAt
        )
    }

    // MARK: Rejection coding

    // Full-precision dates. `.iso8601` would drop sub-second components, so a task written and
    // read back would not compare equal to itself — which the storage contract checks.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func encode(_ rejections: [Rejection]) -> Data {
        (try? encoder.encode(rejections)) ?? Data()
    }

    private static func decode(_ data: Data) -> [Rejection] {
        guard !data.isEmpty else { return [] }
        return (try? decoder.decode([Rejection].self, from: data)) ?? []
    }
}
