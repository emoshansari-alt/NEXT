import Foundation

/// A stretch of work on one task, with an optional timer.
///
/// A **value type that does not tick**. Elapsed time is arithmetic against whatever instant the
/// caller asks about, so nothing here runs, nothing needs cancelling, and a session survives the
/// app being backgrounded or killed without any bookkeeping — the numbers are derived from
/// timestamps, not accumulated by a running clock. It also means every case below is testable
/// off-device (DECISIONS.md D-007).
///
/// NEXT is not a Pomodoro app (PRODUCT_SPEC.md §4.9). The timer is optional and secondary, which
/// is why `plannedMinutes` may be `nil` and why nothing here enforces a break, a cycle, or a
/// streak. A timer running out is information, not a verdict.
public struct FocusSession: Hashable, Sendable {

    public let taskID: TaskID

    /// How long the user chose to work for, or `nil` for no timer.
    public let plannedMinutes: Int?

    public let startedAt: Date

    /// Time banked from earlier running stretches.
    private var bankedSeconds: TimeInterval

    /// When the current running stretch began, or `nil` while paused.
    private var runningSince: Date?

    public init(taskID: TaskID, plannedMinutes: Int?, startedAt: Date) {
        self.taskID = taskID
        self.plannedMinutes = plannedMinutes
        self.startedAt = startedAt
        self.bankedSeconds = 0
        self.runningSince = startedAt
    }

    public var isRunning: Bool { runningSince != nil }

    private var plannedSeconds: TimeInterval? {
        plannedMinutes.map { Double($0) * 60 }
    }

    // MARK: Transitions

    /// Stops the clock. Pausing an already-paused session changes nothing — reachable from a
    /// double tap, or from the app being backgrounded while paused.
    public func paused(at now: Date) -> FocusSession {
        guard let runningSince else { return self }

        var updated = self
        updated.bankedSeconds += max(0, now.timeIntervalSince(runningSince))
        updated.runningSince = nil
        return updated
    }

    /// Starts the clock again. Resuming a running session changes nothing.
    public func resumed(at now: Date) -> FocusSession {
        guard runningSince == nil else { return self }

        var updated = self
        updated.runningSince = now
        return updated
    }

    // MARK: Reading

    /// Time actually spent working. Time spent paused is not work and is not counted.
    public func elapsed(at now: Date) -> TimeInterval {
        guard let runningSince else { return bankedSeconds }
        return bankedSeconds + max(0, now.timeIntervalSince(runningSince))
    }

    /// Time left on the timer, or `nil` when there is no timer.
    ///
    /// `nil` rather than zero, deliberately: zero would render as "0:00 left", which is a
    /// different and untrue claim.
    public func remaining(at now: Date) -> TimeInterval? {
        guard let plannedSeconds else { return nil }
        return max(0, plannedSeconds - elapsed(at: now))
    }

    /// Whether the chosen time is up. A session with no timer never finishes on its own, and a
    /// paused session is not running out.
    public func isFinished(at now: Date) -> Bool {
        guard plannedSeconds != nil, isRunning else { return false }
        return remaining(at: now) == 0
    }

    /// The countdown as it appears on screen, e.g. `"23:30"`.
    public func countdown(at now: Date) -> String? {
        guard let remaining = remaining(at: now) else { return nil }

        let total = Int(remaining.rounded(.down))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// The countdown in words, for VoiceOver.
    ///
    /// A screen reader announcing `"23:30"` as digits is close to useless, and timer state has
    /// to be accessible (PRODUCT_SPEC.md §11). Kept flat and factual — a timer running out is
    /// not a failure and must not read like one.
    public func spokenRemaining(at now: Date) -> String? {
        guard let remaining = remaining(at: now) else { return nil }

        let prefix = isRunning ? "" : "Paused, "

        guard remaining > 0 else { return "Time is up" }

        let seconds = Int(remaining.rounded())
        if seconds < 60 {
            return "\(prefix)\(seconds) second\(seconds == 1 ? "" : "s") left"
        }

        let minutes = seconds / 60
        return "\(prefix)\(minutes) minute\(minutes == 1 ? "" : "s") left"
    }
}
