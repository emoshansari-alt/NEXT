import Foundation

/// Reads the date out of a fragment of a brain dump, deterministically and without a model.
///
/// ## The rule this type follows
///
/// Recognise a small number of phrases exactly, and admit ignorance about everything else. A
/// wrong deadline is materially worse than a missing one: a missing deadline gets asked about on
/// the Capture Confirmation screen, whereas a wrong one silently drives the ranking engine, the
/// Today screen and a notification. So the supported set is small on purpose and every reading
/// carries how sure it is.
///
/// ## What it understands
///
/// | Phrase | Resolves to | Confidence |
/// |---|---|---|
/// | `today`, `tonight` | end of the current local day | high |
/// | `tomorrow` | end of the next local day | high |
/// | a weekday name or common abbreviation | the next occurrence, strictly in the future | low |
/// | `this <weekday>` | the same | low |
/// | `next <weekday>` | the same, trusted less | lower |
///
/// A preposition immediately before the phrase — `on`, `by`, `due`, `for`, `before` — is
/// consumed with it, so the remaining title reads cleanly.
///
/// ## What it deliberately does not understand
///
/// Bare times of day (`at 6` — six in the morning or the evening, today or every week?),
/// calendar dates in any format (`march 14`, `13/03/2026`, `the 14th`), counted offsets
/// (`in three days`, `in a fortnight`), vague spans (`next week`, `end of the month`,
/// `over the weekend`), and urgency words (`asap`). Every one of these is either genuinely
/// ambiguous or needs locale knowledge this layer does not have, and each is left in the title
/// exactly as the user wrote it. Adding any of them is a deliberate change with its own tests,
/// not something to slip in.
///
/// ## Determinism
///
/// `now` and `timeZone` are both parameters. Neither the clock nor the ambient zone is read
/// (DECISIONS.md D-007): "today" has to mean the user's today, and the suite has to be able to
/// state which today it means.
public enum DatePhraseParser {

    /// What one fragment turned out to contain.
    public struct Reading: Hashable, Sendable {

        /// The fragment with the date phrase removed, or unchanged if there was none.
        public let remainingText: String

        /// The instant read, or `nil` if nothing recognisable was there.
        public let date: Date?

        /// How sure the reading is, `nil` when there is no date.
        public let confidence: Double?
    }

    // MARK: - Confidence
    //
    // Stated here rather than inline so the ordering between them is visible at a glance, which
    // is the part that matters: NEXT is more sure about "tomorrow" than about "monday", and more
    // sure about "monday" than about "next monday".

    /// An explicit relative day. The day is unambiguous; only the hour is assumed.
    static let relativeDayConfidence = 0.9

    /// A bare weekday. The day is clear, the hour is assumed, and whether the user meant this
    /// week or the next is genuinely open — so this sits below the confirmation threshold.
    static let weekdayConfidence = 0.7

    /// `next <weekday>`. English does not agree with itself about whether this means the coming
    /// one or the one after, so it is trusted least of the three.
    static let nextWeekdayConfidence = 0.6

    // MARK: - Reading

    public static func read(_ text: String, now: Date, timeZone: TimeZone) -> Reading {
        let words = split(text)
        guard !words.isEmpty else {
            return Reading(remainingText: text, date: nil, confidence: nil)
        }

        guard let match = firstPhrase(in: words) else {
            return Reading(remainingText: text, date: nil, confidence: nil)
        }

        guard let date = resolve(match.phrase, now: now, timeZone: timeZone) else {
            return Reading(remainingText: text, date: nil, confidence: nil)
        }

        // A fragment that was *only* a date leaves nothing to call the task. Better a task named
        // "monday" than a task named nothing at all, so the reading is abandoned rather than
        // producing a nameless row.
        let title = residue(of: match, in: words)
        guard !title.isEmpty else {
            return Reading(remainingText: text, date: nil, confidence: nil)
        }

        return Reading(remainingText: title, date: date, confidence: match.phrase.confidence)
    }

    /// What a fragment would still say once its date phrase had been taken out of it, or `nil`
    /// if there was no phrase to take.
    ///
    /// The companion question to `mentionsDate`, and the more useful of the two: knowing that
    /// "wed" contains a date says nothing about whether it also contains a *task*, and the
    /// answer here — an empty string — says that it does not. Needs no `now`, because it is a
    /// question about the words rather than about the calendar.
    ///
    /// This is exactly the text `read` would keep as the title, produced by the same code, so a
    /// caller can decide in advance whether a reading would leave anything behind.
    public static func datePhraseResidue(_ text: String) -> String? {
        let words = split(text)
        guard let match = firstPhrase(in: words) else { return nil }
        return residue(of: match, in: words)
    }

    /// Whether a piece of text contains any phrase this parser recognises.
    ///
    /// Needs no `now`: it asks whether a date phrase is *present*, not what it resolves to.
    public static func mentionsDate(_ text: String) -> Bool {
        datePhraseResidue(text) != nil
    }

    /// The fragment with the matched phrase — and the preposition that introduced it — removed.
    private static func residue(of match: Match, in words: [String]) -> String {
        // A preposition only belongs to the phrase if the phrase follows it.
        var start = match.range.lowerBound
        if start > 0, prepositions.contains(normalise(words[start - 1])) {
            start -= 1
        }

        var remaining = words
        remaining.removeSubrange(start..<match.range.upperBound)
        return remaining.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func split(_ text: String) -> [String] {
        text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    // MARK: - Phrases

    private enum Phrase: Hashable {
        case today
        case tomorrow
        case weekday(Int)
        case nextWeekday(Int)

        var confidence: Double {
            switch self {
            case .today, .tomorrow: relativeDayConfidence
            case .weekday: weekdayConfidence
            case .nextWeekday: nextWeekdayConfidence
            }
        }
    }

    private struct Match {
        let phrase: Phrase
        let range: Range<Int>
    }

    /// The earliest recognisable phrase in the fragment.
    ///
    /// Earliest rather than last, so the result never depends on how many phrases happen to be
    /// present. Two-word forms are tried before one-word forms at the same position, so that
    /// "next friday" is not read as a bare "friday" with a stray "next" left in the title.
    private static func firstPhrase(in words: [String]) -> Match? {
        for index in words.indices {
            let word = normalise(words[index])

            if index + 1 < words.count, let weekday = weekdays[normalise(words[index + 1])] {
                if word == "next" {
                    return Match(phrase: .nextWeekday(weekday), range: index..<(index + 2))
                }
                if word == "this" {
                    return Match(phrase: .weekday(weekday), range: index..<(index + 2))
                }
            }

            if word == "today" { return Match(phrase: .today, range: index..<(index + 1)) }
            if word == "tonight" { return Match(phrase: .today, range: index..<(index + 1)) }
            if word == "tomorrow" { return Match(phrase: .tomorrow, range: index..<(index + 1)) }

            if let weekday = weekdays[word] {
                return Match(phrase: .weekday(weekday), range: index..<(index + 1))
            }
        }
        return nil
    }

    /// Lower-cased, with surrounding punctuation removed. "friday." and "Friday" are the
    /// same word; "13/03" is not a word at all and will simply match nothing.
    private static func normalise(_ word: String) -> String {
        String(word.lowercased().filter(\.isLetter))
    }

    // MARK: - Resolution

    private static func resolve(_ phrase: Phrase, now: Date, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let today = calendar.startOfDay(for: now)

        let day: Date?
        switch phrase {
        case .today:
            day = today
        case .tomorrow:
            day = calendar.date(byAdding: .day, value: 1, to: today)
        case .weekday(let target), .nextWeekday(let target):
            let current = calendar.component(.weekday, from: today)
            var ahead = (target - current + 7) % 7
            // A weekday naming today means the next one, never a deadline in the past.
            if ahead == 0 { ahead = 7 }
            day = calendar.date(byAdding: .day, value: ahead, to: today)
        }

        guard let day else { return nil }

        // End of the local day. NEXT knows which day the user meant and does not know the hour;
        // the last minute of the day is the reading that cannot make a deadline arrive early.
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day)
    }

    // MARK: - Vocabulary

    /// Weekday names and the abbreviations that actually appear in student shorthand, mapped to
    /// `Calendar`'s 1-based weekday numbers (1 = Sunday).
    ///
    /// "sat", "sun" and "wed" are also ordinary English words. They are accepted anyway, because
    /// "practice sat" is far more likely inside a task list than "sat" as a past tense — and the
    /// consequence of being wrong is a low-confidence date the user is asked about.
    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4, "weds": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7
    ]

    /// Words that introduce a date and belong to it rather than to the title.
    ///
    /// "before friday" is read as "friday", which is very slightly generous. Subtracting a day
    /// the user never mentioned would be a guess, and leaving the word stranded would produce
    /// the title "History slides before".
    private static let prepositions: Set<String> = ["on", "by", "due", "for", "before"]
}
