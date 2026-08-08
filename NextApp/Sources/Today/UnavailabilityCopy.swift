import NextKit

/// Turns an engine outcome into the words the user reads.
///
/// Kept in the app layer so copy can change without touching the engine, and kept in one
/// place so the tone stays consistent. Every string here is a plain statement of fact:
/// nothing scolds, nothing congratulates, nothing implies the user has fallen short (P5).
enum UnavailabilityCopy {

    static func headline(for reason: UnavailabilityReason) -> String {
        switch reason {
        case .noActiveTasks:
            "Nothing left."
        case .nothingFitsAvailableTime:
            "Nothing fits that window."
        case .everythingBlocked:
            "Everything is waiting on something else."
        }
    }

    static func detail(for reason: UnavailabilityReason) -> String {
        switch reason {
        case .noActiveTasks:
            "You have no outstanding tasks."
        case .nothingFitsAvailableTime(let shortestMinutes):
            "The shortest thing you have takes about \(shortestMinutes) minutes."
        case .everythingBlocked:
            "Finish one of the tasks other work depends on to open things up."
        }
    }

    static let emptyHeadline = "Nothing here yet."
    static let emptyDetail = "Add what is on your mind and NEXT will work out where to start."
}
