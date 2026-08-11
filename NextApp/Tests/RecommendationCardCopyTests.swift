import Foundation
import NextKit
import Testing

@testable import NextApp

/// Tier 2. What the recommendation card says below the action.
///
/// `Why this?` was retired because it was a modal repeating the card: the fact line already
/// rendered the explanation whenever a task had a deadline, so tapping it produced an alert
/// saying `Due in 2 days.` beside a card reading `Due in 2 days · ~20 min`. The explanation now
/// lives on the card in every case, which is more of it and fewer taps — and the defect that has
/// to stay fixed is the duplication.
///
/// So the load-bearing test here is the sweep: for **every** reason the engine can produce, the
/// sentence appears in exactly one slot. Not zero, which would lose the explanation the product
/// spec §4.4 requires. Not two, which is what was there before.
@Suite("Recommendation card — the reason appears once")
struct RecommendationCardCopyTests {

    private func recommendation(
        explanation: ExplanationReason,
        estimatedMinutes: Int? = nil,
        deadline: Date? = nil
    ) -> Recommendation {
        Recommendation(
            task: TaskItem(
                id: TaskID("card-copy"),
                title: "History essay",
                createdAt: Date(),
                deadline: deadline,
                estimatedMinutes: estimatedMinutes
            ),
            score: ScoreBreakdown(factors: [:]),
            explanation: explanation,
            deadlineFeasibility: .comfortable,
            wasRecentlyRejected: false
        )
    }

    /// Every case the engine can hand over. Listed rather than derived, because
    /// `ExplanationReason` has associated values and cannot be `CaseIterable` — so a new case
    /// added to the engine will not appear here on its own, and the compiler's exhaustiveness
    /// check inside `RecommendationCardCopy` is what forces someone to decide which slot it goes
    /// in before this file is even reached.
    private var everyReason: [ExplanationReason] {
        [
            .overdue(by: 2 * 24 * 3600),
            .dueSoon(within: 2 * 24 * 3600),
            .unlocksOtherWork(count: 3),
            .markedImportant,
            .fitsTheTimeYouHave(minutes: 20),
            .hasAClearFirstStep,
            .nothingElsePending
        ]
    }

    @Test("every reason is said exactly once, in one slot or the other")
    func theReasonIsNeverLostAndNeverDoubled() {
        for reason in everyReason {
            let lines = RecommendationCardCopy.lines(for: recommendation(explanation: reason))

            // Compared without the full stop, because the fact line drops it and the reason line
            // keeps it — the same sentence in two shapes.
            let stem = reason.sentence.replacingOccurrences(of: ".", with: "")
            let inFacts = lines.facts.contains(stem)
            let inReason = (lines.reason?.contains(stem) == true)

            #expect(inFacts != inReason, "\(reason) is in neither slot or in both")
        }
    }

    @Test("a deadline reads as a fact beside the estimate")
    func theDeadlineJoinsTheFactLine() {
        let lines = RecommendationCardCopy.lines(
            for: recommendation(explanation: .dueSoon(within: 2 * 24 * 3600), estimatedMinutes: 20)
        )

        #expect(lines.facts == "Due in 2 days · ~20 min")
        // Nothing on its own line: it has already been said, and saying it twice on one card is
        // the defect this whole change exists to remove.
        #expect(lines.reason == nil)
    }

    @Test("a reason that is a sentence gets its own line, and keeps its full stop")
    func aSentenceIsNotSquashedIntoTheFactLine() {
        let lines = RecommendationCardCopy.lines(
            for: recommendation(explanation: .hasAClearFirstStep, estimatedMinutes: 15)
        )

        // The fact line stays a list of facts. "Nothing to decide before you start. · ~15 min"
        // is the fragmentary metadata this split exists to avoid.
        #expect(lines.facts == "~15 min")
        #expect(lines.reason == "Nothing to decide before you start.")
    }

    @Test("the shape of the reason decides, not whether the task has a deadline")
    func aDatedTaskWinningOnAnotherFactorStillReadsAsASentence() {
        // The previous rule keyed off `task.deadline != nil` and put whatever the explanation
        // happened to be into the fact line. A task with a distant deadline can win on a
        // different factor entirely, and the card then read
        // "You marked this important · ~20 min" — a sentence wearing a fragment's clothes.
        let lines = RecommendationCardCopy.lines(
            for: recommendation(
                explanation: .markedImportant,
                estimatedMinutes: 20,
                deadline: Date().addingTimeInterval(30 * 24 * 3600)
            )
        )

        #expect(lines.facts == "~20 min")
        #expect(lines.reason == "You marked this important.")
    }

    @Test("a task with no estimate and a dated reason still says the reason")
    func theFactLineSurvivesAMissingEstimate() {
        let lines = RecommendationCardCopy.lines(
            for: recommendation(explanation: .overdue(by: 2 * 24 * 3600))
        )

        #expect(lines.facts == "Overdue by 2 days")
        #expect(lines.reason == nil)
    }

    @Test("nothing is fabricated when the task knows nothing")
    func aBareTaskGetsAReasonAndNoFacts() {
        let lines = RecommendationCardCopy.lines(for: recommendation(explanation: .nothingElsePending))

        #expect(lines.facts.isEmpty)
        #expect(lines.reason == "Nothing else is more pressing right now.")
    }
}
