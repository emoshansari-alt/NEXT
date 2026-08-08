import Foundation

/// Cuts a brain dump into candidate tasks.
///
/// A student typing everything on their mind produces one of about four shapes: a comma list, a
/// line-per-item list, a bulleted list, or one long sentence joined by "and". This splits all
/// four and does not attempt to be cleverer than that.
///
/// Deterministic and pure: same text in, same fragments out, every time, with no clock, no
/// locale and no model involved.
public enum BrainDumpSplitter {

    /// Hard separators. Anything either side of one of these is a different thing to do.
    private static let separators: Set<Character> = [",", ";", "\n", "\r", "\t", "•", "|"]

    /// Leading noise on a list item, stripped once per fragment.
    private static let bulletCharacters: Set<Character> = ["-", "*", "•", "+", "–", "—"]

    /// The candidate tasks in a piece of text, in the order they were written.
    ///
    /// Order is preserved rather than sorted, because the order someone dumps things in is
    /// itself weak information about what is on their mind, and reordering would make the
    /// Capture Confirmation screen disagree with what they just typed.
    public static func fragments(in text: String) -> [String] {
        text
            .split(whereSeparator: { separators.contains($0) })
            .map { stripListMarker(String($0)) }
            .flatMap(splitOnConjunction)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

    /// Splits on " and ", but only when each side carries its own date.
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

        guard DatePhraseParser.mentionsDate(left), DatePhraseParser.mentionsDate(right) else {
            return [fragment]
        }

        // Recurse on the right, so "a mon and b tues and c weds" splits three ways.
        return [left] + splitOnConjunction(right)
    }
}
