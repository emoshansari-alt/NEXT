import Foundation

/// Everything outside the task list that affects which task should be recommended.
///
/// Passing this in — rather than letting the engine reach for the clock or ambient state —
/// is what makes `RankingEngine.recommend` a pure function and therefore honestly testable.
public struct RankingContext: Hashable, Sendable {

    /// The instant the recommendation is being made for.
    public var now: Date

    public init(now: Date) {
        self.now = now
    }
}
