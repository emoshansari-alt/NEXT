import Foundation
import Testing

@testable import NextKit

/// `friction` contributes nothing, on purpose.
///
/// It has been a named zero since Session 1, and this suite is what turns that from an
/// unfinished stub into a decision (`DECISIONS.md` D-022). Anyone giving it a real signal has to
/// come here and delete tests that say why it was zero — which is the point.
@Suite("Ranking — friction is a decided zero")
struct RankingFrictionTests {

    private let engine = RankingEngine()

    private func friction(_ task: TaskItem, among tasks: [TaskItem] = []) -> Double? {
        engine.score(
            task,
            among: tasks.isEmpty ? [task] : tasks,
            context: RankingContext(now: .testReference)
        ).factors[.friction]
    }

    @Test("no shape of task produces any friction")
    func everyTaskShapeScoresZero() {
        // Swept across the shapes that might plausibly have earned a penalty, so this fails the
        // moment a signal is wired in — rather than a single fixture that happens to miss it.
        let shapes: [TaskItem] = [
            makeTask(id: "bare"),
            makeTask(id: "no-step", title: "History essay", estimatedMinutes: 180),
            makeTask(id: "with-step", nextAction: "Open the instructions."),
            makeTask(id: "huge", estimatedMinutes: 600),
            makeTask(id: "overdue", deadline: .daysFromReference(-30)),
            makeTask(id: "started", rejectionsSupersededAt: .testReference),
            makeTask(
                id: "refused",
                rejections: [Rejection(reason: .missingWhatINeed, at: .hoursFromReference(-1))]
            ),
            makeTask(
                id: "long-refused",
                rejections: [Rejection(reason: .needLessEffort, at: .daysFromReference(-40))]
            )
        ]

        for task in shapes {
            #expect(friction(task) == 0, "\(task.id) contributed friction")
        }
    }

    @Test("a task the user has already started is not demoted for it")
    func startingSomethingDoesNotPenaliseIt() {
        // The most tempting friction signal, and the reason it was rejected: "has been started
        // and is still outstanding" describes a task in progress just as well as an abandoned
        // one. Using it would push the user off work they had begun a minute earlier.
        let untouched = makeTask(id: "untouched", deadline: .hoursFromReference(6))
        let started = makeTask(
            id: "started",
            deadline: .hoursFromReference(6),
            rejectionsSupersededAt: .testReference
        )

        let outcome = engine.recommend(
            from: [started, untouched], context: RankingContext(now: .testReference)
        )

        // Identical but for having been started, so the tie breaks on identifier, not on a
        // penalty. What matters is that starting did not cost the task its place.
        #expect(
            engine.score(started, among: [started, untouched], context: RankingContext(now: .testReference)).total
                == engine.score(untouched, among: [started, untouched], context: RankingContext(now: .testReference)).total
        )
        #expect(outcome.recommendation != nil)
    }

    @Test("the factor is still present in every breakdown")
    func frictionIsNamedRatherThanAbsent() {
        // A zero that is written down can be found, explained and later changed. A factor that
        // is simply missing cannot, and "Why this?" is generated from this dictionary.
        let breakdown = engine.score(
            makeTask(id: "any"), among: [makeTask(id: "any")],
            context: RankingContext(now: .testReference)
        )

        #expect(breakdown.factors[.friction] != nil)
        #expect(breakdown.factors.keys.count == RankingFactor.allCases.count)
    }
}
