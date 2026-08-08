/// Why a task scored what it scored.
///
/// Carrying the per-factor contributions rather than a single number is what makes
/// "Why this?" answerable offline and without a model: the explanation is assembled from the
/// largest contributors (PRODUCT_SPEC.md §4.4).
public struct ScoreBreakdown: Hashable, Sendable {

    /// Every `RankingFactor`, always. A factor that does not apply is present and zero —
    /// never omitted, because an absent factor would silently become an absent explanation.
    /// Penalties are already stored negative.
    public let factors: [RankingFactor: Double]

    /// The sum of every contribution. Nothing may be added to a score outside `factors`,
    /// or the explanation would no longer account for the ranking.
    public var total: Double {
        factors.values.reduce(0, +)
    }

    public init(factors: [RankingFactor: Double]) {
        self.factors = factors
    }

    /// The factors that actually pushed this task up, largest first.
    /// Used to generate the "Why this?" sentence.
    public var topPositiveContributors: [(factor: RankingFactor, value: Double)] {
        factors
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                lhs.value == rhs.value
                    ? lhs.key.rawValue < rhs.key.rawValue
                    : lhs.value > rhs.value
            }
            .map { (factor: $0.key, value: $0.value) }
    }
}
