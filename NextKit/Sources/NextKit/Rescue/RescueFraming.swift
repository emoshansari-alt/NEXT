import Foundation

/// The one line that precedes the step.
///
/// Structured rather than a bare string, for the same reasons as `ExplanationReason`: the app
/// layer can reword or localise it without touching this module, and tests can assert on
/// behaviour without pinning copy. `sentence` is the deterministic English default, which is
/// what ships when there is no model and no network.
///
/// Every sentence here is flat. Rescue is reached by someone who is stuck, which is exactly
/// the moment a productivity app is most tempted to cheerlead, and exactly the moment it must
/// not (PRODUCT_SPEC.md §3, P5). No praise, no sympathy, no naming of what the user is feeling.
public enum RescueFraming: Hashable, Sendable {

    /// The first rung of a decomposition.
    case startHere

    /// A later rung, revealed because the user asked for one.
    case thenThis

    /// The size of the task is being deliberately taken off the screen.
    case forgetTheRestForNow

    /// A small, explicitly bounded commitment, after which the user decides again.
    case tinyDeal(minutes: Int)

    /// The task turned out to be shorter than the commitment being offered, so there is no
    /// point offering a slice of it.
    case theWholeThingIsShort(minutes: Int)

    /// The whole task genuinely fits the window the user stated.
    case theWholeThingFits(minutes: Int)

    /// The task does not fit the window, but this one step does.
    case oneStepInTheWindow(minutes: Int)

    /// A short, deterministic English rendering.
    public var sentence: String {
        switch self {
        case .startHere:
            "Start here."

        case .thenThis:
            "Then this."

        case .forgetTheRestForNow:
            "Forget the rest of it for now."

        case .tinyDeal(let minutes):
            "Make the deal tiny. Do \(Self.duration(minutes)), then decide whether to carry on."

        case .theWholeThingIsShort(let minutes):
            "The whole thing is about \(Self.duration(minutes))."

        case .theWholeThingFits(let minutes):
            "The whole thing fits the \(minutes) minutes you have."

        case .oneStepInTheWindow(let minutes):
            "One step that fits the \(minutes) minutes you have."
        }
    }

    /// Reuses the ranking layer's duration wording so Rescue and "Why this?" never disagree
    /// about how to say "5 minutes" (ARCHITECTURE.md §10 — no duplicated logic).
    private static func duration(_ minutes: Int) -> String {
        ExplanationReason.humanised(Double(minutes) * 60)
    }
}
