import Foundation

/// The current instant, as far as the domain layer is concerned.
///
/// This is the time seam from ARCHITECTURE.md §3. Ranking is deadline-driven, so a hidden clock
/// read would make every deadline test time-dependent — "overdue", "due in one hour" and
/// "impossible deadline" could only be tested by contriving the machine's wall clock. Injecting
/// time is the difference between an engine that is testable and one that merely has tests.
///
/// ## There is deliberately no concrete conformance in `NextKit`
///
/// A real clock has to call `Date()`, which DECISIONS.md D-007 bans throughout `NextKit` and
/// `scripts/lint-nextkit.sh` fails the build on. `SystemClock` therefore lives in `NextApp`,
/// where reading the wall clock is legitimate, and tests supply a fixed clock of their own.
///
/// **Do not "complete" this file by adding a `SystemClock` here.** Its absence is the design.
///
/// ## Naming
///
/// The Swift standard library also declares a protocol called `Clock` (the one behind
/// `ContinuousClock` and `Task.sleep`). Inside this module the local declaration wins. In
/// `NextApp`, where both are visible, write `NextKit.Clock` to be unambiguous. The name matches
/// ARCHITECTURE.md §3 and is worth the qualification.
public protocol Clock: Sendable {

    /// The instant to treat as "now".
    ///
    /// Callers read this once and pass the value down as a parameter, rather than handing the
    /// clock itself to the logic underneath. One read per operation means every decision in
    /// that operation is made against a single, consistent instant.
    var now: Date { get }
}
