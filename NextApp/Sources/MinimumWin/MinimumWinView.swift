import NextKit
import SwiftUI

/// Minimum Win — what is still achievable when the whole thing is not.
///
/// PRODUCT_SPEC.md §4.12. Offered only when the ranking engine has already judged the deadline
/// unreachable, so this screen never argues with the one that led here.
///
/// Unlike Rescue, the ladder is shown in full. The user has not asked for the size of the thing
/// to be hidden — they have asked what is still possible — and answering that with one rung at a
/// time would be withholding the choice rather than protecting them from it.
struct MinimumWinView: View {

    let plan: MinimumWinPlan

    /// Called with the rung the user picked.
    var onChoose: (MinimumWinRung) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // States a fact about time and then points at the list. It does not mention
                    // how the situation arose — "you left this too late" is the natural sentence
                    // here and exactly what invariant P5 forbids.
                    Text(plan.framing.sentence)
                        .font(NextType.heading)
                        .foregroundStyle(NextPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("minimum-win-framing")

                    if plan.source.isGeneric {
                        // Generic advice presented as though it were tailored is the small
                        // dishonesty that costs a tool its credibility the first time it is
                        // noticed.
                        Text("These are general stages — NEXT does not know how this one breaks down.")
                            .font(NextType.meta)
                            .foregroundStyle(NextPalette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("minimum-win-generic-notice")
                    }
                } header: {
                    Text(plan.taskTitle)
                }

                Section {
                    ForEach(Array(plan.rungs.enumerated()), id: \.offset) { index, rung in
                        Button {
                            onChoose(rung)
                            dismiss()
                        } label: {
                            row(for: rung)
                        }
                        .accessibilityIdentifier("minimum-win-rung-\(index)")
                    }
                } header: {
                    Text("What still fits")
                }

                if let reassessAt = plan.reassessAt {
                    Section {
                        Text("Come back to this at \(reassessAt.formatted(date: .omitted, time: .shortened)).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("minimum-win-reassess")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NextPalette.desk)
            .navigationTitle("Still possible")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("minimum-win-close-button")
                }
            }
        }
    }

    private func row(for rung: MinimumWinRung) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rung.goal.text)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(NextPalette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail(for: rung))
                .font(NextType.meta)
                .foregroundStyle(NextPalette.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "About 40 minutes", plus the honest note when the goal is not actually reached.
    private func detail(for rung: MinimumWinRung) -> String {
        let duration = "About \(rung.minutes) min"

        guard rung.isTimeBoxed else { return duration }

        // Saying "nothing fits" would be true and useless; presenting this as a completed goal
        // would be a lie. This is the honest third answer.
        return "\(duration) · as far as you get"
    }
}
