import Foundation

/// Everything outside the task list that affects which task should be recommended.
///
/// Passing this in — rather than letting the engine reach for the clock or ambient state —
/// is what makes `RankingEngine.recommend` a pure function and therefore honestly testable.
public struct RankingContext: Hashable, Sendable {

    /// The instant the recommendation is being made for.
    public var now: Date

    /// How long the user has said they have, in minutes. `nil` means they have not said,
    /// which is the normal case — the Today screen does not ask.
    ///
    /// When set, it is a hard constraint: a task that cannot fit is not offered at all.
    /// Suggesting something the user demonstrably cannot finish would break the promise
    /// that the recommended thing is actually startable. Set by Rescue's
    /// "I don't have enough time" path (PRODUCT_SPEC.md §4.11).
    public var availableMinutes: Int?

    public init(now: Date, availableMinutes: Int? = nil) {
        self.now = now
        self.availableMinutes = availableMinutes
    }
}
