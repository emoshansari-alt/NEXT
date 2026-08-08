/// How sure a provider is about one field, from 0 to 1.
///
/// A separate type rather than a bare `Double` because the range is the whole point. A response
/// claiming `1.4` confidence is not "very sure" — it is malformed, and it must not be clamped
/// into looking reasonable. The failable initialiser is the only public way to make one, so a
/// `Confidence` that exists has already been proved to be in range.
///
/// Note what this type does *not* decide: whether a value is high enough to act on. That
/// threshold is a product judgement and lives with the other tuneable constants in
/// `ValidationLimits`, so there is exactly one place to change it (ARCHITECTURE.md §10).
public struct Confidence: Hashable, Sendable, Comparable, CustomStringConvertible {

    public let value: Double

    /// Returns `nil` for anything outside `0...1`, and for anything that is not a finite
    /// number. Failing rather than clamping keeps "out of range" reportable as the validation
    /// failure it is.
    public init?(_ value: Double) {
        guard value.isFinite, value >= 0, value <= 1 else { return nil }
        self.value = value
    }

    /// For the two literals below only. Private so that every other route in or out of this
    /// type goes through the range check.
    private init(literal value: Double) {
        self.value = value
    }

    /// Complete certainty. Used where a value did not come from inference at all — the user's
    /// own words carried through unchanged.
    public static let certain = Confidence(literal: 1)

    /// What a provider that said nothing about a field is taken to have meant.
    ///
    /// Zero, not one. A response that carries a deadline and no confidence for it has not
    /// claimed the deadline is right — it has failed to claim anything, and the only safe
    /// reading of silence is "ask". Because this sits below any sane confirmation threshold,
    /// an unstated value is always routed to the user rather than written through.
    public static let unstated = Confidence(literal: 0)

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
        lhs.value < rhs.value
    }

    public var description: String { "\(value)" }
}
