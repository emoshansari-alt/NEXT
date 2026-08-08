/// One named contribution to a task's priority score.
///
/// Scores are never anonymous numbers. Every factor is named, so the winning task's top
/// contributors can be turned into the "Why this?" sentence without asking a model
/// (PRODUCT_SPEC.md §4.4). A breakdown always contains *every* case, explicitly zero when it
/// does not apply — an omitted factor is a missing explanation.
public enum RankingFactor: String, Hashable, Sendable, CaseIterable {

    /// How close the deadline is. The dominant factor.
    case deadlineUrgency

    /// The user marked it Important.
    case importance

    /// Finishing this unblocks other work.
    case unlockValue

    /// The deadline has already passed.
    case overdueRelevance

    /// There is a concrete, known first step, so it is easy to begin.
    case startability

    /// It fits the time and circumstances the user has right now.
    case contextualFit

    /// Something makes it harder to begin than its size suggests. Reduces the score.
    case friction

    /// The user recently said "Not this". Reduces the score.
    case rejectionPenalty

    /// Whether this factor can only ever reduce a score.
    var isPenalty: Bool {
        switch self {
        case .friction, .rejectionPenalty: true
        default: false
        }
    }
}
