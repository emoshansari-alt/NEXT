import NextKit
import SwiftUI

/// "I'm stuck" — Rescue.
///
/// A first-class feature, not a help page, and deliberately **not** a chatbot
/// (PRODUCT_SPEC.md §4.11). Four named ways of being stuck, each with its own strategy, all
/// answered from `RescueStrategy` in `NextKit` — deterministic, offline, no model involved.
///
/// One step is shown at a time on purpose. Momentum matters more than exposing the whole
/// decomposition: seeing the full ladder is the same experience as seeing the whole task, which
/// is what the user just said was too much.
struct RescueView: View {

    let task: TaskItem
    let allTasks: [TaskItem]
    var now: Date = Date()

    /// Called when the user takes the small step and wants to get on with it.
    var onStart: (RescueResponse) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var path: RescuePath?
    @State private var budget: TimeBudget?
    @State private var response: RescueResponse?
    @State private var unavailable: UnavailabilityReason?

    private let strategy = RescueStrategy()

    var body: some View {
        NavigationStack {
            Group {
                if let response {
                    guidance(response)
                } else if let unavailable {
                    nothingAvailable(unavailable)
                } else if path?.needsTimeBudget == true {
                    timeBudgetChooser
                } else {
                    pathChooser
                }
            }
            .navigationTitle("Stuck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("rescue-close-button")
                }
            }
        }
    }

    // MARK: Choosing a path

    private var pathChooser: some View {
        VStack(spacing: 14) {
            Text("What is in the way?")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                // Wraps rather than clips once the type is large — the audit caught this being
                // cut off, which on this screen means the question itself becomes unreadable.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .accessibilityIdentifier("rescue-question")

            // Four options and no free-text field. The paths are closed on purpose — an open
            // box would make this a chatbot, and the product is explicit that it is not one.
            ForEach(RescuePath.allCases, id: \.self) { option in
                Button {
                    choose(option)
                } label: {
                    Text(option.prompt)
                        .multilineTextAlignment(.center)
                        // The four paths are the whole screen. A prompt that clips is a choice the
                        // user cannot read, so the button grows instead — 52 is a floor, not a
                        // ceiling.
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("rescue-path-\(option.rawValue)")
            }

            Spacer()
        }
        .padding(20)
    }

    private var timeBudgetChooser: some View {
        VStack(spacing: 14) {
            Text("How long have you got?")
                .font(.title3.weight(.semibold))
                .padding(.top, 8)
                .accessibilityIdentifier("rescue-time-question")

            ForEach(TimeBudget.allCases, id: \.self) { option in
                Button {
                    budget = option
                    resolve()
                } label: {
                    Text(option.label)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("rescue-budget-\(option.rawValue)")
            }

            Spacer()
        }
        .padding(20)
    }

    // MARK: The answer

    private func guidance(_ response: RescueResponse) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                // `lines` is built in NextKit and tested there, including a check that nothing
                // it produces reads as a judgement.
                ForEach(Array(response.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("rescue-guidance")

            Spacer()

            Button {
                onStart(response)
                dismiss()
            } label: {
                Text("Do that")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("rescue-start-button")

            Button("Something else") { reset() }
                .font(.subheadline)
                .accessibleTapTarget()
                .padding(.top, 14)
                .accessibilityIdentifier("rescue-back-button")
        }
        .padding(24)
    }

    private func nothingAvailable(_ reason: UnavailabilityReason) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(UnavailabilityCopy.headline(for: reason))
                .font(.title3.weight(.semibold))
            Text(UnavailabilityCopy.detail(for: reason))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Something else") { reset() }
                .accessibleTapTarget()
                .accessibilityIdentifier("rescue-back-button")
        }
        .padding(24)
        .accessibilityIdentifier("rescue-nothing-available")
    }

    // MARK: Wiring

    private func choose(_ option: RescuePath) {
        path = option
        guard !option.needsTimeBudget else { return }
        resolve()
    }

    private func resolve() {
        guard let path else { return }

        switch path {
        case .dontKnowHowToStart:
            response = strategy.dontKnowHowToStart(with: task, among: allTasks)
        case .tooMuch:
            response = strategy.tooMuch(with: task, among: allTasks)
        case .dontWantTo:
            response = strategy.dontWantTo(with: task, among: allTasks)
        case .notEnoughTime:
            guard let budget else { return }
            // The only path that re-ranks: the user has changed the constraints, so the best
            // thing to do may no longer be the task they were looking at.
            switch strategy.notEnoughTime(budget, from: allTasks, now: now) {
            case .guidance(let result): response = result
            case .nothingAvailable(let reason): unavailable = reason
            case .nothingToDo: unavailable = .noActiveTasks
            }
        }
    }

    private func reset() {
        path = nil
        budget = nil
        response = nil
        unavailable = nil
    }
}
