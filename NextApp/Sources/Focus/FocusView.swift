import NextKit
import SwiftUI

/// Focus. Everything unrelated disappears.
///
/// PRODUCT_SPEC.md §4.9. No task list, no navigation chrome, no counters. The only things on
/// screen are the action and the ways out of it.
///
/// The timer is deliberately absent from this first slice rather than stubbed — NEXT is not a
/// Pomodoro app and the timer is optional and secondary. It arrives in Phase 6 with its own
/// tests, including the accessibility requirement that timer state be announced.
struct FocusView: View {

    let task: TaskItem
    let onDone: () -> Void
    let onStop: () -> Void

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
                HStack {
                    Button("Stop", action: onStop)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("focus-stop-button")
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

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

                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
                .accessibilityIdentifier("focus-done-button")
            }
        }
    }
}
