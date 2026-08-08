import Foundation
import Testing

@testable import NextKit

// Deterministic date reading, with no model and no network.
//
// Every test pins "now" to Tuesday 10 March 2026, 09:00 UTC (`Date.testReference`), and states
// its time zone. Both are parameters, never ambient (DECISIONS.md D-007) — a parser that read
// the clock or the device's zone would give a different answer to the same sentence depending on
// where and when the suite ran.
//
// The other half of these tests is at least as important as the first: the phrases the parser
// deliberately does *not* understand. Guessing wrong about a due date is worse than admitting
// ignorance, because an admitted gap gets asked about and a wrong date does not.

private func read(
    _ text: String,
    now: Date = .testReference,
    timeZone: TimeZone = testTimeZone
) -> DatePhraseParser.Reading {
    DatePhraseParser.read(text, now: now, timeZone: timeZone)
}

@Suite("Date phrases — relative days")
struct RelativeDayPhraseTests {

    @Test("tomorrow is the end of the following day")
    func tomorrow() {
        let reading = read("finish slides tomorrow")

        #expect(reading.date == iso("2026-03-11T23:59:00Z"))
        #expect(reading.remainingText == "finish slides")
    }

    @Test("today is the end of the current day")
    func today() {
        #expect(read("email professor today").date == iso("2026-03-10T23:59:00Z"))
    }

    @Test("tonight is the end of the current day too")
    func tonight() {
        // Not 6pm, not 9pm. NEXT knows the day and does not know the hour, and inventing one
        // would be a guess wearing a deadline's clothes.
        #expect(read("practice tonight").date == iso("2026-03-10T23:59:00Z"))
    }

    @Test("a relative day is confident, because there is nothing ambiguous about it")
    func relativeDaysAreConfident() throws {
        let threshold = ValidationLimits.default.confirmationThreshold

        for phrase in ["today", "tomorrow", "tonight"] {
            let confidence = try #require(read("do the thing \(phrase)").confidence)
            #expect(confidence >= threshold, "\(phrase) came back at \(confidence)")
        }
    }
}

@Suite("Date phrases — weekdays")
struct WeekdayPhraseTests {

    @Test("every weekday resolves to its next occurrence")
    func everyWeekday() {
        // Reference is Tuesday 10 March 2026.
        let expected: [String: String] = [
            "wednesday": "2026-03-11T23:59:00Z",
            "thursday": "2026-03-12T23:59:00Z",
            "friday": "2026-03-13T23:59:00Z",
            "saturday": "2026-03-14T23:59:00Z",
            "sunday": "2026-03-15T23:59:00Z",
            "monday": "2026-03-16T23:59:00Z"
        ]

        for (day, instant) in expected.sorted(by: { $0.key < $1.key }) {
            #expect(read("chem test \(day)").date == iso(instant), "\(day)")
        }
    }

    @Test("a weekday naming today means next week, never a deadline that has already passed")
    func todaysWeekdayMeansNextWeek() {
        // "chem test tuesday", typed on a Tuesday morning, almost never means "in fifteen
        // hours". Resolving strictly forwards is both deterministic and the safer of the two
        // readings: a deadline a week late is visible and fixable, one in the past is neither.
        #expect(read("chem test tuesday").date == iso("2026-03-17T23:59:00Z"))
    }

    @Test("the common abbreviations are understood")
    func abbreviations() {
        let expected: [String: String] = [
            "mon": "2026-03-16T23:59:00Z",
            "tue": "2026-03-17T23:59:00Z",
            "tues": "2026-03-17T23:59:00Z",
            "wed": "2026-03-11T23:59:00Z",
            "weds": "2026-03-11T23:59:00Z",
            "thu": "2026-03-12T23:59:00Z",
            "thur": "2026-03-12T23:59:00Z",
            "thurs": "2026-03-12T23:59:00Z",
            "fri": "2026-03-13T23:59:00Z",
            "sat": "2026-03-14T23:59:00Z",
            "sun": "2026-03-15T23:59:00Z"
        ]

        for (abbreviation, instant) in expected.sorted(by: { $0.key < $1.key }) {
            #expect(read("paper \(abbreviation)").date == iso(instant), "\(abbreviation)")
        }
    }

    @Test("a bare weekday is read, and not read as certain")
    func bareWeekdayIsNotCertain() throws {
        // The day is clear; the hour is not, and neither is whether the user meant this week or
        // the one after. That is exactly the state Capture Confirmation exists for.
        let confidence = try #require(read("chem test monday").confidence)

        #expect(confidence > 0)
        #expect(confidence < ValidationLimits.default.confirmationThreshold)
    }

    @Test("\"next friday\" is understood, and trusted less than \"friday\"")
    func nextWeekdayIsLessCertain() throws {
        // English does not agree with itself here: on a Tuesday, "next Friday" means the coming
        // Friday to some people and the one after to others. NEXT picks the nearer reading and
        // says plainly that it is less sure, rather than picking one and sounding certain.
        let bare = try #require(read("paper friday").confidence)
        let next = try #require(read("paper next friday").confidence)

        #expect(read("paper next friday").date == iso("2026-03-13T23:59:00Z"))
        #expect(next < bare)
    }

    @Test("\"this friday\" is understood")
    func thisWeekday() {
        #expect(read("paper this friday").date == iso("2026-03-13T23:59:00Z"))
    }
}

@Suite("Date phrases — what is deliberately not understood")
struct UnsupportedDatePhraseTests {

    @Test("a bare time of day is not a deadline")
    func bareTimeIsNotADate() {
        // "practice at 6" is the case from PRODUCT_SPEC.md §4.5, and it is genuinely ambiguous:
        // six in the morning or the evening, today or on some recurring schedule. NEXT keeps the
        // user's words in the title and records no deadline at all.
        let reading = read("practice at 6")

        #expect(reading.date == nil)
        #expect(reading.remainingText == "practice at 6")
    }

    @Test("phrases outside the supported set are left alone rather than guessed at")
    func unsupportedPhrases() {
        for text in [
            "essay in three days",
            "paper due march 14",
            "chem test 13/03/2026",
            "reading by the end of the month",
            "slides next week",
            "sort this out asap",
            "revision over the weekend",
            "lab report in a fortnight"
        ] {
            let reading = read(text)
            #expect(reading.date == nil, "read a date out of: \(text)")
            #expect(reading.remainingText == text, "altered: \(text)")
        }
    }

    @Test("a fragment that is nothing but a date keeps its text, so no titleless task appears")
    func dateOnlyFragmentKeepsItsText() {
        // Removing the only word present would leave a task with no name, which is worse than a
        // task called "Monday".
        let reading = read("monday")

        #expect(reading.date == nil)
        #expect(reading.remainingText == "monday")
    }
}

@Suite("Date phrases — determinism")
struct DatePhraseDeterminismTests {

    @Test("the answer moves with the injected now, and only with it")
    func answerFollowsNow() {
        let earlier = read("chem test monday", now: .testReference)
        let laterSameWeek = read("chem test monday", now: .daysFromReference(1))
        let followingWeek = read("chem test monday", now: .daysFromReference(7))

        #expect(earlier.date == iso("2026-03-16T23:59:00Z"))
        #expect(laterSameWeek.date == iso("2026-03-16T23:59:00Z"))
        #expect(followingWeek.date == iso("2026-03-23T23:59:00Z"))
    }

    @Test("the injected time zone decides which day the user is having")
    func answerFollowsTimeZone() throws {
        // 09:00 UTC on Tuesday is still Monday evening eleven hours west, and Tuesday night
        // thirteen hours east. "Today" has to mean the user's today.
        let west = TimeZone(secondsFromGMT: -11 * 3600) ?? testTimeZone
        let east = TimeZone(secondsFromGMT: 13 * 3600) ?? testTimeZone

        #expect(read("email professor today", timeZone: west).date
            == iso("2026-03-10T10:59:00Z"))
        #expect(read("finish slides tomorrow", timeZone: east).date
            == iso("2026-03-11T10:59:00Z"))
    }

    @Test("every part of a reading is fixed: the title, the instant and the confidence")
    func repeatedReadsAgree() {
        // `read(text) == read(text)` is true of any pure function, including one that returned
        // the same wrong answer twice, so it could never have gone red. Determinism is pinned by
        // writing the answer down instead — all three fields, because a reading that got the
        // date right and quietly kept "monday" in the title would still be wrong.
        let weekday = read("chem test monday")
        #expect(weekday.remainingText == "chem test")
        #expect(weekday.date == iso("2026-03-16T23:59:00Z"))
        #expect(weekday.confidence == 0.7)

        let relativeDay = read("slides tomorrow")
        #expect(relativeDay.remainingText == "slides")
        #expect(relativeDay.date == iso("2026-03-11T23:59:00Z"))
        #expect(relativeDay.confidence == 0.9)

        // Nothing recognised: the text comes back untouched and no confidence is offered,
        // because there is no reading to be confident about.
        let noPhrase = read("practice at 6")
        #expect(noPhrase.remainingText == "practice at 6")
        #expect(noPhrase.date == nil)
        #expect(noPhrase.confidence == nil)
    }

    @Test("a preposition in front of the date goes with it")
    func prepositionsAreConsumed() {
        // "before friday" is read as "friday", which is very slightly generous. The alternative
        // is subtracting a day the user never mentioned, and a silent subtraction is a guess;
        // leaving the word stranded in the title — "History slides before" — is just broken.
        for text in ["history slides by friday", "history slides on friday",
                     "history slides due friday", "history slides before friday"] {
            let reading = read(text)
            #expect(reading.date == iso("2026-03-13T23:59:00Z"), "\(text)")
            #expect(reading.remainingText == "history slides", "\(text)")
        }
    }
}
