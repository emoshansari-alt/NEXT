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
                        .foregroundStyle(NextPalette.inkSecondary)
                }
            }
            .listStyle(.insetGrouped)
            // The same treatment the other native-list screens get (D-023): rows on the card
            // stock, so the palette's contrast guarantees apply to what is actually rendered.
            // This screen was missed when Settings and Task Detail were done, and extending the
            // audit past the writing stage is what found it.
            .listRowBackgroundIsCard()
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
                // A symbol's own bounds are the whole target without this — well under 44 points,
                // on the control that decides whether a captured task is kept. The audit found it
                // the first time this screen was audited at all.
                .frame(minWidth: NextMetrics.tapTarget, minHeight: NextMetrics.tapTarget)
                .contentShape(.rect)
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
                .font(NextType.body)
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
                        .foregroundStyle(NextPalette.inkSecondary)
                        .accessibilityIdentifier("deadline-uncertain")
                }

                Spacer()

                // Was a caption-height text button: about fourteen points tall, which is what the
                // audit reported as an unattributed "Hit area is too small". `quietText` carries
                // the 44-point guarantee, which is why the app has a style for this at all
                // rather than each screen inventing one.
                Button("Clear") { model.setDeadline(nil, forProposal: proposal.id) }
                    .buttonStyle(.quietText)
                    .accessibilityIdentifier("deadline-clear-button")
            }
        } else {
            HStack {
                Text("No deadline")
                    .font(.caption)
                    .foregroundStyle(NextPalette.inkSecondary)
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
                    .foregroundStyle(NextPalette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("confirmation-failure")
            }

            // Outlined secondary beside the one filled primary, which is D-023's rule rather
            // than a restyle for its own sake. The system's `.bordered` drew "Edit" in the
            // accent on the bar's material and failed contrast outright; `.borderedProminent`
            // beside it would have been the second filled block the direction forbids.
            HStack(spacing: 12) {
                Button("Edit") { model.returnToWriting() }
                    .buttonStyle(.outlinedBlock)
                    .accessibilityIdentifier("confirmation-edit-button")

                Button("Looks right") { Task { await model.confirm() } }
                    .buttonStyle(.primaryBlock)
                    .disabled(savedCount == 0)
                    .accessibilityIdentifier("confirmation-accept-button")
            }
        }
        .padding(20)
        // The palette's own surface, not the system's `.bar` material.
        //
        // "Edit" failed contrast as NEXT's ink on that material, which is the same finding D-021
        // records for a section header rendered against the navigation bar: a material has no
        // colour the palette can be measured against, so any text NEXT draws on one is
        // unverifiable by construction. `card` is a real value, and `NextPaletteTests` already
        // proves both ink tokens against it.
        .background(NextPalette.card)
        .announcesFailure(model.failure)
    }
}
