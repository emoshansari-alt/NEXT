import Foundation

/// Cuts a brain dump into candidate tasks.
///
/// A student typing everything on their mind produces one of about five shapes: a comma list, a
/// line-per-item list, a bulleted list, a few ordinary sentences, or one long sentence joined by
/// "and". This splits all five and does not attempt to be cleverer than that.
///
/// Deterministic and pure: same text in, same fragments out, every time, with no clock, no
/// locale and no model involved.
public enum BrainDumpSplitter {

    /// Hard separators. Anything either side of one of these is a different thing to do.
    private static let separators: Set<Character> = [",", ";", "\n", "\r", "\t", "•", "|"]

    /// Leading noise on a list item, stripped once per fragment.
    private static let bulletCharacters: Set<Character> = ["-", "*", "•", "+", "–", "—"]

    /// Words that end in a full stop without ending a sentence.
    ///
    /// Short and specific rather than a general abbreviation dictionary. Each one is a form that
    /// really does turn up in a student's list immediately before a name or a continuation, and
    /// cutting at it would split a person in half — "Email Prof. Hale" becoming "Email Prof" and
    /// "Hale". Weekday abbreviations are deliberately *not* here: "chem test mon. email prof" is
    /// two things and should separate.
    private static let nonTerminalAbbreviations: Set<String> = [
        "prof", "dr", "mr", "mrs", "ms", "etc", "eg", "ie", "vs"
    ]

    /// The candidate tasks in a piece of text, in the order they were written.
    ///
    /// Order is preserved rather than sorted, because the order someone dumps things in is
    /// itself weak information about what is on their mind, and reordering would make the
    /// Capture Confirmation screen disagree with what they just typed.
    public static func fragments(in text: String) -> [String] {
        sentences(in: text)
            .flatMap { $0.split(whereSeparator: { separators.contains($0) }) }
            .map { stripListMarker(String($0)) }
            .flatMap(splitOnConjunction)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Cuts the text at each full stop that genuinely ends a sentence.
    ///
    /// Pasting from Notes or from a message is an ordinary way to capture, and what arrives is
    /// punctuated prose rather than a comma list. Leaving the full stop out of the separator set
    /// does not merely fail to split — it is actively worse than that, because `DatePhraseParser`
    /// then reads the date out of the *middle* of the merged text and hands back a sentence the
    /// user never wrote with a word missing from it: "Chem test monday. Email professor." became
    /// the single task "Chem test Email professor.".
    ///
    /// A full stop only counts when whitespace follows it, so decimals ("1.5 hour room") and file
    /// names are untouched, and so is the full stop that ends the whole dump — that one is the
    /// user's own punctuation at the end of their own last item, and there is nothing after it to
    /// separate from.
    private static func sentences(in text: String) -> [String] {
        let characters = Array(text)
        var pieces: [String] = []
        var pieceStart = 0
        var wordStart = 0

        for index in characters.indices {
            let character = characters[index]

            if character.isWhitespace || separators.contains(character) {
                wordStart = index + 1
                continue
            }

            guard character == ".",
                  index + 1 < characters.count,
                  characters[index + 1].isWhitespace,
                  endsASentence(String(characters[wordStart..<index]))
            else { continue }

            pieces.append(String(characters[pieceStart..<index]))
            pieceStart = index + 1
            wordStart = index + 1
        }

        pieces.append(String(characters[pieceStart...]))
        return pieces
    }

    /// Whether the word immediately before a full stop is one that a sentence can end on.
    ///
    /// Three things it is not. A run of digits is a numbered list marker or a chapter number —
    /// cutting at "1." would turn item one of a list into a task called "1". A single letter is
    /// an initial, so "J. K. Rowling" stays one name. And a handful of abbreviations carry a full
    /// stop mid-sentence by convention.
    private static func endsASentence(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        guard !word.allSatisfy(\.isNumber) else { return false }
        guard word.count > 1 else { return false }
        return !nonTerminalAbbreviations.contains(word.lowercased())
    }

    /// Removes a leading bullet or "1." / "2)" numbering.
    ///
    /// Only leading, and only once. A hyphen in the middle of a fragment is part of what the
    /// user wrote — "re-read chapter 4" is one task, not a bullet.
    private static func stripListMarker(_ fragment: String) -> String {
        var text = fragment.trimmingCharacters(in: .whitespacesAndNewlines)

        if let first = text.first, bulletCharacters.contains(first) {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            return text
        }

        let digits = text.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3 else { return text }

        let afterDigits = text.dropFirst(digits.count)
        guard let punctuation = afterDigits.first, punctuation == "." || punctuation == ")" else {
            // "20 minute reading" is a task, not item twenty of a list.
            return text
        }

        return String(afterDigits.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    /// Splits on " and ", but only when each side is a dated obligation in its own right.
    ///
    /// "and" is the hardest separator in the language to act on. It joins two obligations
    /// ("chem thing thurs and paper next friday") and it joins two halves of one phrase ("black
    /// and white photos"), and nothing shallow tells them apart reliably.
    ///
    /// Word counts do not work: "print the black and white photos" has three words on the left
    /// and two on the right, and cutting it produces "Print the black" and "White photos" —
    /// two pieces of nonsense the user then has to delete and repair. A deadline on each side
    /// does work, because a phrase-internal "and" does not have one.
    ///
    /// A date on each side is necessary and not sufficient. "practice mon and wed" is how a
    /// student writes a standing commitment, and the right-hand side of it is *nothing but* a
    /// weekday: cutting there leaves a fragment with no words to name a task with, and
    /// `DatePhraseParser` will not strip the only word a fragment has — so the result is a task
    /// called "Wed", with no deadline, that the user never wrote and now has to delete. Each
    /// side must therefore still say something once its date is taken out of it, which is what
    /// `datePhraseResidue` reports.
    ///
    /// The rule is therefore deliberately conservative, and the asymmetry of the two mistakes is
    /// why. Splitting wrongly produces two broken tasks and makes NEXT look like it did not read
    /// the sentence. Failing to split leaves one honest task holding two things, which is still
    /// usable, still visible on the Capture Confirmation screen, and still the user's own words.
    /// When in doubt, do not cut up what someone wrote.
    private static func splitOnConjunction(_ fragment: String) -> [String] {
        let words = fragment.split(separator: " ", omittingEmptySubsequences: true)

        guard let index = words.firstIndex(where: { $0.lowercased() == "and" }) else {
            return [fragment]
        }

        let left = words[words.startIndex..<index].joined(separator: " ")
        let right = words[words.index(after: index)...].joined(separator: " ")

        guard let leftRemainder = DatePhraseParser.datePhraseResidue(left),
              let rightRemainder = DatePhraseParser.datePhraseResidue(right),
              !leftRemainder.isEmpty,
              !rightRemainder.isEmpty
        else {
            return [fragment]
        }

        // Recurse on the right, so "a mon and b tues and c weds" splits three ways.
        return [left] + splitOnConjunction(right)
    }
}
