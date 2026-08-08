/// The four ways into Rescue.
///
/// A closed set, deliberately. Rescue is a first-class feature with four known shapes of
/// stuckness, and it must never degrade into an open chatbot (PRODUCT_SPEC.md §4.11): there is
/// no free-text entry point here and adding one would be a product defect, not a feature.
///
/// The four are not variations on one answer. Each changes what the user is shown — how much
/// of the task is visible, whether more steps are admitted to exist, and what is being asked
/// of them. Collapsing them into a single "here is a smaller step" would lose the feature.
public enum RescuePath: String, Hashable, Sendable, CaseIterable, Codable {

    /// Shrink to the smallest meaningful physical action, one rung at a time.
    case dontKnowHowToStart

    /// Hide the size of the thing and show one small step.
    case tooMuch

    /// Fit the highest-value achievable action into a stated window.
    case notEnoughTime

    /// Reduce the friction. No diagnosis, no lecture.
    case dontWantTo

    /// What the user taps. Written in the user's own voice, which is why these read as
    /// admissions rather than as labels — the app is not narrating their state back at them.
    public var prompt: String {
        switch self {
        case .dontKnowHowToStart: "I don't know how to start"
        case .tooMuch: "It's too much"
        case .notEnoughTime: "I don't have enough time"
        case .dontWantTo: "I just don't want to do it"
        }
    }

    /// Whether the path needs the user to say how long they have before it can answer.
    /// Only one does, and asking on the others would add a decision for no gain (P1).
    public var needsTimeBudget: Bool {
        self == .notEnoughTime
    }
}
