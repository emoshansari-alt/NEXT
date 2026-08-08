/// How long the user says they have.
///
/// Four fixed windows rather than free entry: picking from four is one decision, typing a
/// number is a decision plus an estimate, and the user came here because deciding is the
/// problem (P1). The values are the ones the product spec names (PRODUCT_SPEC.md §4.11).
public enum TimeBudget: Int, Hashable, Sendable, CaseIterable, Codable {

    case five = 5
    case fifteen = 15
    case thirty = 30
    case sixty = 60

    /// The window in minutes, ready to hand to `RankingContext.availableMinutes`.
    public var minutes: Int { rawValue }

    /// A short label for the button.
    public var label: String {
        self == .sixty ? "1 hour" : "\(minutes) min"
    }

    /// Rebuilds a budget from a stored minute count. Fails on anything that is not one of
    /// the four, rather than silently rounding to a window the user never chose.
    public init?(minutes: Int) {
        self.init(rawValue: minutes)
    }
}
