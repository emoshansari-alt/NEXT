import Foundation

/// Every bound the validator enforces, in one place.
///
/// Same rule as `ScoringWeights` and `MinimumWinWeights`, for the same reason (DECISIONS.md
/// D-008, ARCHITECTURE.md §10): a limit buried in a `guard` cannot be reviewed, cannot be tuned,
/// and cannot be argued with. Every number below states why it is the number it is.
///
/// These are *plausibility* bounds, not correctness bounds. Their job is to stop nonsense
/// reaching the task database, not to second-guess a reasonable answer. When a bound and a real
/// student's real task disagree, the bound is wrong.
public struct ValidationLimits: Hashable, Sendable {

    // MARK: Sizes

    /// Longest acceptable task title.
    ///
    /// Generous on purpose. A brain-dump fragment is whatever the user typed between two
    /// commas, and a long one is untidy rather than malicious. Beyond this it is not a title,
    /// it is a paragraph, and the honest answer is to send the user to manual entry rather than
    /// to truncate their own words on their behalf.
    public var maxTitleLength: Int

    /// Longest acceptable generated instruction.
    ///
    /// Shorter than a title, because a step is read by someone who is stuck. "Open the
    /// assignment instructions." is 38 characters; anything approaching this bound has stopped
    /// being an instruction.
    public var maxStepLength: Int

    /// Most tasks one response may contain.
    ///
    /// A brain dump is what is on a student's mind, not an import format. Fifty is far past any
    /// real dump and still small enough that a runaway response cannot flood the database.
    public var maxTasksPerResponse: Int

    /// Most steps one decomposition may contain.
    ///
    /// Twelve. Rescue reveals one rung at a time, and a decomposition longer than this is the
    /// mountain the user came here to stop looking at (PRODUCT_SPEC.md §4.11).
    public var maxStepsPerDecomposition: Int

    // MARK: Durations

    /// Shortest acceptable estimate. Zero minutes is not an estimate, it is a missing field.
    public var minEstimatedMinutes: Int

    /// Longest acceptable estimate, in minutes.
    ///
    /// One day. Not because no assignment takes longer, but because *one task* that takes
    /// longer has not been broken down yet — and an estimate of "three weeks" cannot drive
    /// Focus, the time-budget filter, or Minimum Win.
    public var maxEstimatedMinutes: Int

    // MARK: Dates

    /// How far before `now` a deadline may still be, in seconds.
    ///
    /// A year. Overdue is a normal state (invariant P4) and NEXT must never treat a late task
    /// as corrupt data. Past this, the model has misread a year and the date is noise.
    public var earliestDeadlineOffset: TimeInterval

    /// How far after `now` a deadline may be, in seconds.
    ///
    /// Three years — longer than the rest of most undergraduate degrees, and short enough that
    /// the year 3000 is caught. This is the bound that stops a hallucinated century from
    /// silently becoming a task the ranking engine considers forever unurgent.
    public var latestDeadlineOffset: TimeInterval

    // MARK: Confidence

    /// At or above this, a value is acted on. Below it, the user is asked.
    ///
    /// 0.75 is a judgement, not a measurement, and it is stated here so it can be tuned with
    /// evidence later. It sits deliberately high: PRODUCT_SPEC.md §4.6 says ambiguous deadlines
    /// ask rather than invent certainty, and the cost of one extra tap is far below the cost of
    /// a wrong due date driving the Today screen.
    public var confirmationThreshold: Double

    // MARK: Tone

    /// Phrases that make generated text a product defect rather than a suggestion.
    ///
    /// Invariant P5 forbids productivity morality and PRODUCT_SPEC.md §1 forbids clinical
    /// framing. A model that has never read either can produce both, so the gate checks.
    ///
    /// The list is deliberately narrow and phrase-based rather than word-based. It targets
    /// second-person judgement and explicit diagnosis of the *user*; it is a last line of
    /// defence, not a content filter. It is applied only to text NEXT would be *saying* — never
    /// to a task title, which is the user's own words about their own work.
    ///
    /// Every entry must be a phrase that can only be NEXT talking about the person reading it.
    /// A word stem cannot be, and a stem here is a bug rather than extra safety: "diagnos"
    /// rejects "Read the diagnostic criteria section." and a bare "your brain" rejects "Open the
    /// neuroscience notes on your brain stem." Both are ordinary undergraduate coursework, and
    /// because failure is wholesale, one of them discards the entire decomposition and drops the
    /// user to the generic ladder for a task NEXT had understood perfectly well. A screen that
    /// fires on the user's own subject matter costs more than it protects.
    public var forbiddenInGeneratedText: [String]

    public init(
        maxTitleLength: Int,
        maxStepLength: Int,
        maxTasksPerResponse: Int,
        maxStepsPerDecomposition: Int,
        minEstimatedMinutes: Int,
        maxEstimatedMinutes: Int,
        earliestDeadlineOffset: TimeInterval,
        latestDeadlineOffset: TimeInterval,
        confirmationThreshold: Double,
        forbiddenInGeneratedText: [String]
    ) {
        self.maxTitleLength = maxTitleLength
        self.maxStepLength = maxStepLength
        self.maxTasksPerResponse = maxTasksPerResponse
        self.maxStepsPerDecomposition = maxStepsPerDecomposition
        self.minEstimatedMinutes = minEstimatedMinutes
        self.maxEstimatedMinutes = maxEstimatedMinutes
        self.earliestDeadlineOffset = earliestDeadlineOffset
        self.latestDeadlineOffset = latestDeadlineOffset
        self.confirmationThreshold = confirmationThreshold
        self.forbiddenInGeneratedText = forbiddenInGeneratedText
    }

    /// The shipping limits.
    public static let `default` = ValidationLimits(
        maxTitleLength: 400,
        maxStepLength: 240,
        maxTasksPerResponse: 50,
        maxStepsPerDecomposition: 12,
        minEstimatedMinutes: 1,
        maxEstimatedMinutes: 60 * 24,
        earliestDeadlineOffset: -365 * 24 * 60 * 60,
        latestDeadlineOffset: 3 * 365 * 24 * 60 * 60,
        confirmationThreshold: 0.75,
        forbiddenInGeneratedText: [
            // Judgement of the user.
            "lazy",
            "you failed",
            "you have failed",
            "you keep failing",
            "falling behind",
            "fell behind",
            "you're behind",
            "you are behind",
            "streak",
            "you should have",
            "no excuse",
            "pathetic",
            "procrastinator",
            "stop making excuses",

            // Diagnosis of the user.
            "your adhd",
            "you have adhd",
            "with your adhd",
            "executive dysfunction",
            "your anxiety",
            "your depression",
            "your condition",
            "your disorder",
            "your symptoms",
            "you have been diagnosed",
            "your diagnosis",
            "diagnose yourself",

            // Second-person claims about how the reader's mind works. Narrow on purpose: the
            // bare phrase "your brain" belongs to a neuroscience reading list at least as often
            // as to a lecture about the user.
            "your brain can't",
            "your brain cannot",
            "your brain isn't wired",
            "your brain is not wired"
        ]
    )
}
