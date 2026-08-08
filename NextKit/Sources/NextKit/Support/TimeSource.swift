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
/// A real time source has to call `Date()`, which DECISIONS.md D-007 bans throughout `NextKit`
/// and `scripts/lint-nextkit.sh` fails the build on. `SystemTimeSource` therefore lives in
/// `NextApp`, where reading the wall clock is legitimate, and tests supply a fixed one of their
/// own.
///
/// **Do not "complete" this file by adding a `SystemTimeSource` here.** Its absence is the
/// design.
///
/// ## Why not `Clock`
///
/// The standard library already declares a protocol called `Clock` — the one behind
/// `ContinuousClock`, `Task.sleep(until:)` and `InstantProtocol`. A second `Clock` vended by
/// this module competes with it in any file importing both.
///
/// What that costs in practice was observed, not assumed: while the seam was still called
/// `Clock`, its own test file could not conform to it without writing `NextKit.Clock`, and had
/// to spell the existential `any NextKit.Clock`. Precisely which uses resolve silently and
/// which the compiler rejects depends on what else is in scope — and having to work that out
/// per call site is itself the problem.
///
/// A seam whose name makes callers stop and disambiguate is a badly named seam. `TimeSource`
/// says the same thing, collides with nothing, and needs no qualification anywhere.
public protocol TimeSource: Sendable {

    /// The instant to treat as "now".
    ///
    /// Callers read this once and pass the value down as a parameter, rather than handing the
    /// time source itself to the logic underneath. One read per operation means every decision
    /// in that operation is made against a single, consistent instant.
    var now: Date { get }
}
