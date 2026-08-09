import NextKit
import SwiftUI

/// Capture Confirmation — the screen that keeps AI advisory.
///
/// PRODUCT_SPEC.md §4.6: every consequential inference is confirmable, deadlines especially.
/// A date the app inferred but is not confident about appears here as a **question**, marked and
/// unset, never quietly written as though the user had said it. Silently inventing certainty is
/// the defect this screen exists to prevent.
///
/// The user can untick anything extraction got wrong about how many things they wrote, and fix a
/// title in place. Nothing has been saved yet.
struct CaptureConfirmationView: View {

    @State var model: CaptureViewModel

    private var savedCount: Int {
        model.proposals.filter { $0.isIncluded && $0.isSaveable }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.proposals) { proposal in
                    row(proposal)
                }

                if model.proposals.isEmpty {
                    Text("NEXT could not find any tasks in that.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            // On the list, not on the enclosing stack. A container's identifier propagates to
            // its children and would overwrite every control's own — including the accept
            // button in the footer below.
            .accessibilityIdentifier("capture-confirmation")

            footer
        }
    }

    // MARK: Row

    private func row(_ proposal: CaptureProposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button {
                    model.setIncluded(!proposal.isIncluded, forProposal: proposal.id)
                } label: {
                    Image(systemName: proposal.isIncluded ? "checkmark.circle.fill" : "circle")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                // Meaning never rests on the tick alone.
                .accessibilityLabel(proposal.isIncluded ? "Included" : "Not included")
                .accessibilityIdentifier("proposal-toggle")

                TextField(
                    "Task",
                    text: Binding(
                        get: { proposal.title },
                        set: { model.setTitle($0, forProposal: proposal.id) }
                    )
                )
                .font(.body)
                .accessibilityLabel("Task name")
            }

            deadlineRow(proposal)
                .padding(.leading, 36)
        }
        .padding(.vertical, 4)
        .opacity(proposal.isIncluded ? 1 : 0.45)
    }

    @ViewBuilder
    private func deadlineRow(_ proposal: CaptureProposal) -> some View {
        if let deadline = proposal.deadline {
            HStack(spacing: 8) {
                DatePicker(
                    "Due",
                    selection: Binding(
                        get: { deadline },
                        set: { model.setDeadline($0, forProposal: proposal.id) }
                    ),
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .accessibilityLabel("Due date")

                if proposal.deadlineNeedsConfirmation {
                    // Stated in words, not signalled by colour. The app is not sure, and says so.
                    Text("Is this right?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("deadline-uncertain")
                }

                Spacer()

                Button("Clear") { model.setDeadline(nil, forProposal: proposal.id) }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Text("No deadline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            if let failure = model.failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("confirmation-failure")
            }

            HStack(spacing: 12) {
                Button("Edit") { model.returnToWriting() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("confirmation-edit-button")

                Button {
                    Task { await model.confirm() }
                } label: {
                    Text("Looks right")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(savedCount == 0)
                .accessibilityIdentifier("confirmation-accept-button")
            }
        }
        .padding(20)
        .background(.bar)
        .announcesFailure(model.failure)
    }
}
