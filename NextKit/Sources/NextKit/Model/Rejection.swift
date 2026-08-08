import Foundation

/// A record of the user saying "Not this" to a recommendation.
///
/// Stored rather than acted on immediately, because the penalty has to *decay*: a task turned
/// down an hour ago should come back this afternoon, not be exiled. Keeping the history also
/// leaves the door open to learning from rejection rate, which the product spec identifies as
/// the most valuable signal for tuning the engine.
public struct Rejection: Hashable, Sendable, Codable {

    public let reason: RejectionReason

    /// When the user rejected it. Supplied by the caller — `NextKit` never reads the clock.
    public let at: Date

    public init(reason: RejectionReason, at: Date) {
        self.reason = reason
        self.at = at
    }
}

/// Why the user turned a recommendation down.
///
/// These are exactly the five options offered in the UI (PRODUCT_SPEC.md §4.3). They are
/// deliberately about *circumstance*, never about the user's character or willingness —
/// there is no "I'm being lazy" option, because P5 forbids productivity morality.
public enum RejectionReason: String, Hashable, Sendable, Codable, CaseIterable {

    /// "Can't do it right now."
    case cantRightNow

    /// "Don't have what I need."
    case missingWhatINeed

    /// "Need something shorter."
    case needSomethingShorter

    /// "Need less effort."
    case needLessEffort

    /// "Something else."
    case other
}
