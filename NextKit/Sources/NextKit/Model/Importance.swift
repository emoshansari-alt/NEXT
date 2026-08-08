/// How much a task matters, as the user sees it.
///
/// Deliberately two values, not five. The product spec caps the public priority control at
/// Normal / Important for 1.0: every extra level is a decision the user has to make, and
/// P1 says reduce decisions rather than create them. More levels are added only if testing
/// proves they are needed.
public enum Importance: String, Hashable, Sendable, Codable, CaseIterable {
    case normal
    case important

    /// Normalised contribution to the ranking score, before weighting.
    var signal: Double {
        switch self {
        case .normal: 0
        case .important: 1
        }
    }
}
