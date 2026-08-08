import Foundation

/// Mints identities for newly captured tasks.
///
/// This is the identity seam from ARCHITECTURE.md §3, and it exists for the same reason as
/// `TimeSource`: a hidden source of randomness makes results unreproducible. With identifiers
/// injected, a brain dump of five tasks produces the same five identifiers every run, so tie
/// breaks, ordering and persistence round-trips can all be asserted exactly.
///
/// ## There is deliberately no concrete conformance in `NextKit`
///
/// A real provider has to call `UUID()`, which DECISIONS.md D-007 bans throughout `NextKit` and
/// `scripts/lint-nextkit.sh` fails the build on. `UUIDProvider` therefore lives in `NextApp`,
/// and tests supply a sequential provider of their own.
///
/// **Do not "complete" this file by adding a `UUIDProvider` here.** Its absence is the design.
public protocol IDProvider: Sendable {

    /// Returns an identifier that has not been issued before by this provider.
    ///
    /// Deliberately **not** `mutating`, so the seam can be held as `any IDProvider` and shared
    /// freely. A provider that counts rather than randomises therefore has to synchronise its
    /// own state — that cost is the implementation's, not every call site's.
    func makeTaskID() -> TaskID
}
