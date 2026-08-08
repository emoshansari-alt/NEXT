import Foundation

/// The kind of work a task looks like, inferred from its title alone.
///
/// This exists so that Rescue can offer a *physical* first step — "Open the assignment
/// instructions." — instead of the useless "start the task". It is a deliberately shallow,
/// deterministic keyword match, not a model and not an attempt at understanding: PRODUCT_SPEC
/// §6 says AI must earn its usage, and this layer is precisely what has to work when there is
/// no network and no model at all.
///
/// Inference is the *second* choice. Anything the user actually recorded — a next action, real
/// substeps — outranks it (see `StepShrinker`). When nothing here matches, Rescue falls back to
/// an honest generic step rather than a confident wrong one.
public enum WorkKind: String, Hashable, Sendable, CaseIterable, Codable {

    /// Writing to someone: an email, a message, a reply.
    case correspondence

    /// Paperwork: submitting, uploading, printing, registering, paying.
    case admin

    /// A set of questions to work through.
    case problemSet

    /// Something to be shown to a room: slides, a poster, a talk.
    case presentation

    /// Preparing for an exam or test.
    case revision

    /// Repetition of a skill: an instrument, a drill, a rehearsal.
    case practice

    /// Producing prose: an essay, a paper, a report.
    case writing

    /// Getting through a text.
    case reading

    // MARK: - Steps

    /// The ladder of first physical steps for this kind of work, smallest first.
    ///
    /// Every entry names something the user can *do with their hands in the next minute* —
    /// open a thing, put a thing in front of them, write one line. A step that requires a
    /// decision first ("plan the essay") would recreate the exact problem Rescue exists to
    /// solve. Tone is flat on purpose: no encouragement, no commentary (PRODUCT_SPEC.md §3).
    public var firstSteps: [String] {
        switch self {
        case .correspondence:
            [
                "Open a new message and fill in the recipient.",
                "Write the subject line.",
                "Write one sentence saying what you need."
            ]

        case .admin:
            [
                "Find the link or form you need and open it.",
                "Fill in the first field.",
                "Send it off."
            ]

        case .problemSet:
            [
                "Open the worksheet.",
                "Read question 1.",
                "Answer question 1."
            ]

        case .presentation:
            [
                "Open the slides.",
                "Add a title slide.",
                "Write the three points you want to make."
            ]

        case .revision:
            [
                "Open your notes for this topic.",
                "Read the first section once.",
                "Cover the page and write down what you remember."
            ]

        case .practice:
            [
                "Set out what you need.",
                "Do the first five minutes at the easiest level.",
                "Repeat the hardest part once."
            ]

        case .writing:
            [
                "Open the assignment instructions.",
                "Open a blank document and type the title.",
                "Write one paragraph."
            ]

        case .reading:
            [
                "Open the text to where you left off.",
                "Read the first page.",
                "Write down one line about what it said."
            ]
        }
    }

    // MARK: - Inference

    /// The kind of work the title suggests, or `nil` when nothing in it is a signal.
    ///
    /// Two passes, in this order:
    ///
    /// 1. **Action verbs.** "Read the essay" is reading, even though "essay" names a written
    ///    artefact — the verb says what the user is actually going to do.
    /// 2. **Object nouns.** "History essay" has no verb, so the artefact decides.
    ///
    /// Within a pass, the keyword appearing *earliest* in the title wins: "Read chapter 4 and
    /// write a summary" starts with reading, which is both deterministic and usually right.
    /// A tie at the same word is broken by declaration order, so the result never depends on
    /// set iteration order.
    public static func inferred(fromTitle title: String) -> WorkKind? {
        let words = tokens(in: title)
        return match(words, \.verbs) ?? match(words, \.objects)
    }

    private static func match(
        _ words: [String],
        _ keywords: KeyPath<WorkKind, Set<String>>
    ) -> WorkKind? {
        for word in words {
            let singular = singularised(word)
            if let kind = allCases.first(where: {
                let set = $0[keyPath: keywords]
                return set.contains(word) || set.contains(singular)
            }) {
                return kind
            }
        }
        return nil
    }

    /// Lower-cased words, split on anything that is not a letter. Digits and punctuation are
    /// separators, so "chapter 4," and "questions 1-5" tokenise cleanly.
    static func tokens(in title: String) -> [String] {
        title.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    /// A crude plural strip, enough for "essays" and "worksheets". Irregular plurals that
    /// matter are listed in the keyword sets outright.
    private static func singularised(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }

    // MARK: - Keywords
    //
    // Kept disjoint within each pass so that a match is never ambiguous. Stored in singular
    // form where `singularised` can reach the plural.

    /// Words describing the act itself.
    var verbs: Set<String> {
        switch self {
        case .correspondence:
            ["email", "emailing", "emailed", "message", "messaging",
             "reply", "replying", "respond", "responding", "contact", "phone"]

        case .admin:
            ["submit", "submitting", "upload", "uploading", "print", "printing",
             "register", "registering", "renew", "apply", "applying", "pay", "paying",
             "enrol", "enroll"]

        case .problemSet:
            // "answer" is deliberately absent. It is the ordinary verb for replying to a
            // person as well as for working a question, so "Answer Professor Hale's email"
            // matched here and offered "Open the worksheet." A real problem set almost always
            // names its artefact too — question, worksheet, homework — so the object pass
            // catches "Answer question 3" without the verb, and correspondence keeps its own.
            ["solve", "solving", "calculate", "calculating"]

        case .presentation:
            ["present", "presenting"]

        case .revision:
            ["revise", "revising", "study", "studying", "review", "reviewing",
             "memorise", "memorize", "memorising", "memorizing", "cram", "cramming"]

        case .practice:
            ["practise", "practising", "practice", "practicing",
             "rehearse", "rehearsing", "drill", "drilling", "train", "training"]

        case .writing:
            ["write", "writing", "wrote", "draft", "drafting", "type", "typing",
             "summarise", "summarize", "outline"]

        case .reading:
            ["read", "reading", "skim", "skimming", "annotate", "annotating"]
        }
    }

    /// Words naming the thing being worked on. Consulted only when no verb matched.
    var objects: Set<String> {
        switch self {
        case .correspondence:
            // Nothing reliable: "professor" or "reply" as a noun appear just as often inside
            // tasks that are not correspondence at all. The verbs carry this kind.
            []

        case .admin:
            ["form", "paperwork", "registration", "fee", "receipt", "application"]

        case .problemSet:
            ["worksheet", "problem", "exercise", "question", "homework", "sum"]

        case .presentation:
            ["slide", "deck", "presentation", "poster"]

        case .revision:
            ["exam", "test", "quiz", "quizzes", "midterm", "revision", "flashcard"]

        case .practice:
            ["piano", "guitar", "violin", "scale", "rehearsal", "workout"]

        case .writing:
            ["essay", "paper", "report", "thesis", "dissertation",
             "blog", "article", "coursework"]

        case .reading:
            // "page" is deliberately absent. A page is a unit of almost every kind of work —
            // a title page, a cover page, a web page — so it named the artefact only by
            // accident, and "Make a title page for the essay" was answered with "Open the
            // text to where you left off." The verbs and the remaining nouns carry this kind.
            ["chapter", "book", "textbook", "novel", "reading"]
        }
    }
}
