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

    /// What is being worked on — the task *and* the action, which are not always the same thing.
    let target: FocusTarget

    /// Every task, so "I'm stuck" can re-rank without leaving Focus.
    var allTasks: [TaskItem] = []

    let onDone: () -> Void
    let onStop: () -> Void

    /// Called when Rescue, opened from inside Focus, offers a smaller step.
    var onRescued: (RescueResponse) -> Void = { _ in }

    /// Injected so tests and previews can pin the clock.
    var timeSource: any TimeSource = SystemTimeSource()

    @State private var session: FocusSession?
    @State private var now: Date = .distantPast
    @State private var showingRescue = false

    /// Drives the countdown. One second is enough for a display that only shows minutes and
    /// seconds, and the session itself is derived from timestamps — this only decides how often
    /// the screen re-reads it, never what the answer is.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Spacer()

                VStack(spacing: 14) {
                    // Shown only when it adds context the action does not already carry — and
                    // taken from the target, so a path that deliberately withheld the task's name
                    // is not undone here.
                    if let parentTitle = target.parentTitle {
                        Text(parentTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text(target.action)
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
        // A smaller action is a different piece of work, so the length chosen for the previous
        // one does not carry over. Dropping back to the chooser costs one tap and avoids putting
        // someone on a countdown they set for something else.
        .onChange(of: target.action) { _, _ in session = nil }
        .sheet(isPresented: $showingRescue) {
            RescueView(
                task: target.task,
                allTasks: allTasks,
                onStart: { response in onRescued(response) }
            )
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button("Stop", action: onStop)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibleTapTarget()
                .accessibilityIdentifier("focus-stop-button")

            Spacer()

            // Required by PRODUCT_SPEC.md §4.9, and it is the moment it matters most: being
            // stuck happens *while* working, and someone who has to leave Focus, find Today and
            // hunt for the way out has already lost the thread.
            Button("I'm stuck") { showingRescue = true }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibleTapTarget()
                .accessibilityIdentifier("focus-im-stuck-button")
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
                    Text(FocusCopy.doneLabel(for: target))
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
        session = FocusSession(taskID: target.task.id, plannedMinutes: minutes, startedAt: startedAt)
    }
}

/// Focus's few words.
enum FocusCopy {

    /// What the primary button promises.
    ///
    /// A reduced action gets a different label because it does a different thing: finishing a
    /// step Rescue shrank out of an essay does not finish the essay, and a button that says
    /// "Done" while leaving the task open — or worse, closes it — is the app being unclear about
    /// the one action that cannot be undone by hand.
    static func doneLabel(for target: FocusTarget) -> String {
        target.completesTask ? "Done" : "Done with this step"
    }
}
