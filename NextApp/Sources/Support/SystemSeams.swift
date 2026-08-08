import Foundation
import NextKit

/// The real clock.
///
/// This lives in `NextApp` and not in `NextKit` for a concrete reason, not a stylistic one:
/// it has to call `Date()`, and `scripts/lint-nextkit.sh` fails the build on any `Date()` inside
/// `NextKit` (DECISIONS.md D-007). The seam is a protocol there and a implementation here, so
/// the domain layer stays a pure function of the time it is handed.
struct SystemTimeSource: TimeSource {
    var now: Date { Date() }
}

/// The real identifier source.
///
/// Same reasoning as `SystemTimeSource`: `UUID()` is banned inside `NextKit`, so the only place
/// an identifier can actually be minted is here.
struct UUIDProvider: IDProvider {
    func makeTaskID() -> TaskID {
        TaskID(UUID().uuidString)
    }
}
