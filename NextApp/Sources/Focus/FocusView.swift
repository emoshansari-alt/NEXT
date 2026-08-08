import NextKit
import SwiftUI

/// Focus. Everything unrelated disappears.
///
/// PRODUCT_SPEC.md §4.9. No task list, no navigation chrome, no counters. The only things on
/// screen are the action and the ways out of it.
///
/// The timer is optional and chosen *before* the clock starts, so nobody is put on a countdown
/// they did not ask for. NEXT is not a Pomodoro app: there is no cycle, no enforced break, and
/// nothing accumulates between sessions.
struct FocusView: View {

    let task: TaskItem
    let onDone: () -> Void
    let onStop: () -> Void

    /// Injected so tests and previews can pin the clock.
    var timeSource: any TimeSource = SystemTimeSource()

    @State private var session: FocusSession?
    @State private var now: Date = .distantPast

    /// Drives the countdown. One second is enough for a display that only shows minutes and
    /// seconds, and the session itself is derived from timestamps — this only decides how often
    /// the screen re-reads it, never what the answer is.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var actionText: String {
        guard let next = task.nextAction?.trimmingCharacters(in: .whitespacesAndNewlines),
              !next.isEmpty
        else { return task.title }
        return next
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Spacer()

                VStack(spacing: 14) {
                    // Shown only when it adds context the action itself does not carry.
                    if actionText != task.title {
                        Text(task.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text(actionText)
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 32)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("focus-action")

                Spacer()

                if let session {
                    running(session)
                } else {
                    timerChooser
                }
            }
        }
        .onAppear { now = timeSource.now }
        .onReceive(tick) { _ in now = timeSource.now }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button("Stop", action: onStop)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("focus-stop-button")
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: Choosing a length

    private var timerChooser: some View {
        VStack(spacing: 12) {
            Text("How long?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach([5, 15, 25, 45], id: \.self) { minutes in
                    Button("\(minutes)m") { start(minutes: minutes) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("focus-timer-\(minutes)")
                        .accessibilityLabel("\(minutes) minutes")
                }
            }

            // Listed alongside the presets rather than hidden, because working without a timer
            // is a normal choice and not an opt-out.
            Button {
                start(minutes: nil)
            } label: {
                Text("Just start")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
            .accessibilityIdentifier("focus-start-button")
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 32)
    }

    // MARK: Running

    @ViewBuilder
    private func running(_ session: FocusSession) -> some View {
        VStack(spacing: 16) {
            if let countdown = session.countdown(at: now) {
                Text(countdown)
                    .font(.system(size: 44, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(session.isRunning ? .primary : .secondary)
                    // The digits are hidden from VoiceOver and the words are announced instead:
                    // "23:30" read aloud as digits is close to useless.
                    .accessibilityHidden(true)

                Text(session.spokenRemaining(at: now) ?? "")
                    .accessibilityIdentifier("focus-timer-status")
                    .frame(width: 0, height: 0)
                    .clipped()
                    .accessibilityLabel(session.spokenRemaining(at: now) ?? "")

                if session.isFinished(at: now) {
                    // A statement, not a verdict. The user decides what happens next.
                    Text("That is the time you set.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button(session.isRunning ? "Pause" : "Resume") {
                    self.session = session.isRunning
                        ? session.paused(at: timeSource.now)
                        : session.resumed(at: timeSource.now)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("focus-pause-button")

                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("focus-done-button")
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 32)
    }

    private func start(minutes: Int?) {
        let startedAt = timeSource.now
        now = startedAt
        session = FocusSession(taskID: task.id, plannedMinutes: minutes, startedAt: startedAt)
    }
}
