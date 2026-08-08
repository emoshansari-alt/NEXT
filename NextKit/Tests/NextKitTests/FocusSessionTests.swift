import Foundation
import Testing

@testable import NextKit

// The Focus timer (PRODUCT_SPEC.md §4.9). A value type rather than a ticking object: the view
// re-reads elapsed time against the current instant, so nothing runs, and pausing across the app
// being backgrounded or killed is arithmetic rather than bookkeeping.
//
// NEXT is not a Pomodoro app. The timer is optional and secondary, which is why `plannedMinutes`
// may be nil and why nothing here enforces a break, a cycle, or a streak.
//
// Note the helper names: `mark(_:)` rather than `at(_:)`. Writing `paused(at: at(5))` — a
// function whose name matches an argument label, nested inside it — reliably crashed the Swift
// 6.3.3 Windows compiler with "compile command failed due to exception 3".

private let sessionStart = Date.testReference

private func newSession(minutes: Int? = 25) -> FocusSession {
    FocusSession(taskID: TaskID("chem"), plannedMinutes: minutes, startedAt: sessionStart)
}

/// The instant `minutes` after the session began.
private func mark(_ minutes: Double) -> Date {
    sessionStart.addingTimeInterval(minutes * 60)
}

@Suite("FocusSession — running time")
struct FocusSessionRunningTests {

    @Test("a fresh session has run for no time at all")
    func startsAtZero() {
        #expect(newSession().elapsed(at: sessionStart) == 0)
    }

    @Test("elapsed time is measured against the clock, not counted")
    func elapsedTracksTheClock() {
        let elapsed = newSession().elapsed(at: mark(10))

        #expect(elapsed == 600)
    }

    @Test("remaining time counts down from the planned length")
    func remainingCountsDown() {
        let remaining = newSession().remaining(at: mark(10))

        #expect(remaining == 900)
    }

    @Test("a session with no timer has no remaining time to report")
    func noTimerMeansNoRemaining() {
        // nil, not zero — zero would render as "0:00 left", which is a different claim.
        let session = newSession(minutes: nil)

        #expect(session.remaining(at: mark(10)) == nil)
        #expect(session.isFinished(at: mark(500)) == false)
    }

    @Test("remaining time never goes negative")
    func remainingFloorsAtZero() {
        #expect(newSession().remaining(at: mark(40)) == 0)
    }

    @Test("the session is finished once the planned time is up")
    func finishesWhenPlannedTimeElapses() {
        let session = newSession()

        #expect(session.isFinished(at: mark(24)) == false)
        #expect(session.isFinished(at: mark(25)))
        #expect(session.isFinished(at: mark(26)))
    }
}

@Suite("FocusSession — pausing")
struct FocusSessionPauseTests {

    @Test("a paused session stops accumulating time")
    func pausedTimeDoesNotCount() {
        let paused = newSession().paused(at: mark(5))

        #expect(paused.elapsed(at: mark(5)) == 300)
        #expect(paused.elapsed(at: mark(30)) == 300, "time spent paused is not work")
    }

    @Test("resuming continues from where it stopped")
    func resumingContinues() {
        let resumed = newSession().paused(at: mark(5)).resumed(at: mark(20))

        #expect(resumed.elapsed(at: mark(20)) == 300)
        #expect(resumed.elapsed(at: mark(25)) == 600)
    }

    @Test("several pauses accumulate correctly")
    func repeatedPausesAccumulate() {
        // 5 minutes worked, paused, 3 more worked, paused, then 2 more.
        let interrupted = newSession()
            .paused(at: mark(5))
            .resumed(at: mark(10))
            .paused(at: mark(13))
            .resumed(at: mark(40))

        #expect(interrupted.elapsed(at: mark(42)) == 600)
    }

    @Test("pausing an already-paused session changes nothing")
    func pausingTwiceIsHarmless() {
        // Reachable from a double tap, or the app being backgrounded while already paused.
        let once = newSession().paused(at: mark(5))
        let twice = once.paused(at: mark(9))

        #expect(twice.elapsed(at: mark(30)) == once.elapsed(at: mark(30)))
    }

    @Test("resuming a running session changes nothing")
    func resumingTwiceIsHarmless() {
        let running = newSession()
        let resumed = running.resumed(at: mark(5))

        #expect(resumed.elapsed(at: mark(10)) == running.elapsed(at: mark(10)))
    }

    @Test("a session reports whether it is running")
    func pauseStateIsReadable() {
        #expect(newSession().isRunning)
        #expect(newSession().paused(at: mark(3)).isRunning == false)
        #expect(newSession().paused(at: mark(3)).resumed(at: mark(4)).isRunning)
    }

    @Test("a paused session does not finish while it is paused")
    func pausedSessionsDoNotFinish() {
        let paused = newSession(minutes: 5).paused(at: mark(2))

        #expect(paused.isFinished(at: mark(60)) == false, "a paused timer is not running out")
    }
}

@Suite("FocusSession — what the screen shows")
struct FocusSessionDisplayTests {

    @Test("the countdown reads as minutes and seconds")
    func countdownIsFormatted() {
        let session = newSession()

        #expect(session.countdown(at: sessionStart) == "25:00")
        #expect(session.countdown(at: mark(1.5)) == "23:30")
        #expect(session.countdown(at: mark(24.5)) == "0:30")
        #expect(session.countdown(at: mark(30)) == "0:00")
    }

    @Test("a session with no timer has no countdown to show")
    func noTimerHasNoCountdown() {
        #expect(newSession(minutes: nil).countdown(at: mark(10)) == nil)
    }

    @Test("the spoken form is words, not a clock face")
    func spokenFormIsReadable() {
        // VoiceOver reading "25:00" as digits is close to useless, and timer state has to be
        // accessible (PRODUCT_SPEC.md §11).
        let session = newSession()

        #expect(session.spokenRemaining(at: sessionStart) == "25 minutes left")
        #expect(session.spokenRemaining(at: mark(24)) == "1 minute left")
        #expect(session.spokenRemaining(at: mark(24.5)) == "30 seconds left")
        #expect(session.spokenRemaining(at: mark(25)) == "Time is up")
        #expect(newSession(minutes: nil).spokenRemaining(at: mark(10)) == nil)
    }

    @Test("a paused session says so when spoken")
    func spokenFormMentionsPause() {
        let paused = newSession().paused(at: mark(5))

        #expect(paused.spokenRemaining(at: mark(30)) == "Paused, 20 minutes left")
    }

    @Test("nothing the timer says pressures the user")
    func timerLanguageIsNeutral() {
        // P5. A timer running out is information, not a verdict, and must not read like one.
        let banned = ["hurry", "quick", "failed", "behind", "only"]

        var samples: [String] = []
        samples.append(newSession().spokenRemaining(at: sessionStart) ?? "")
        samples.append(newSession().spokenRemaining(at: mark(24.9)) ?? "")
        samples.append(newSession().spokenRemaining(at: mark(25)) ?? "")
        samples.append(newSession().paused(at: mark(1)).spokenRemaining(at: mark(5)) ?? "")

        for sample in samples {
            for word in banned {
                #expect(!sample.lowercased().contains(word), "'\(word)' in: \(sample)")
            }
        }
    }
}
