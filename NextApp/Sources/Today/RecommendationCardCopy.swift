import NextKit

/// What the recommendation card says about itself, below the action.
///
/// ## Why this is a type rather than two computed properties on the view
///
/// The card has two slots of different shapes, and the explanation has to land in exactly one of
/// them. The fact line is a row of short facts joined by a middle dot — `Due in 2 days · ~20 min`
/// — and a full sentence does not belong in it. The reason line is a sentence and a fragment does
/// not belong there either.
///
/// Deciding both together is what makes "exactly one" structural. `Why this?` was retired because
/// it was a modal that repeated the card whenever a task had a deadline, and the way to not
/// reintroduce that defect is to make it impossible to say the same thing twice rather than to
/// remember not to.
enum RecommendationCardCopy {

    struct Lines: Equatable {

        /// Short facts, joined by a middle dot. Empty when there are none.
        let facts: String

        /// The explanation, as a sentence on its own line — or `nil` when it is already in
        /// `facts`, which is the case whenever the reason is the deadline.
        let reason: String?
    }

    static func lines(for recommendation: Recommendation) -> Lines {
        var facts: [String] = []
        var reason: String?

        // Split on the shape of the reason rather than on whether the task has a deadline.
        //
        // Those two are not the same question, and using the second was a small existing defect:
        // a task with a distant deadline can win on a different factor entirely, and the fact
        // line would then read "You marked this important · ~20 min" — a sentence wearing a
        // fragment's clothes. Only the two deadline reasons render as fragments.
        switch recommendation.explanation {
        case .overdue, .dueSoon:
            // The trailing stop is dropped because this is joining a list of facts, not ending a
            // sentence. "Due in 2 days · ~20 min".
            facts.append(
                recommendation.explanation.sentence.replacingOccurrences(of: ".", with: "")
            )

        case .unlocksOtherWork, .markedImportant, .fitsTheTimeYouHave,
             .hasAClearFirstStep, .nothingElsePending:
            reason = recommendation.explanation.sentence
        }

        if let minutes = recommendation.task.estimatedMinutes {
            facts.append("~\(minutes) min")
        }

        return Lines(facts: facts.joined(separator: " · "), reason: reason)
    }
}
