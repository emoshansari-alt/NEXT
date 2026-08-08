import NextKit
import SwiftUI

/// Capture — one text field, two ways out.
///
/// The field is the whole screen. There are no pickers for deadline, duration, importance or
/// tags: capture must not make the user organise anything (PRODUCT_SPEC.md §4.5), because the
/// moment it does, the cost of writing something down goes up and things stop getting written
/// down. Structure is extracted afterwards, and only ever confirmed, never assumed.
struct CaptureView: View {

    @State var model: CaptureViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case .writing:
                    writing
                case .confirming:
                    CaptureConfirmationView(model: model)
                case .saved(let count):
                    saved(count: count)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("capture-cancel-button")
                }
            }
        }
    }

    private var title: String {
        switch model.stage {
        case .writing: "Add"
        case .confirming: "Is this right?"
        case .saved: "Saved"
        }
    }

    // MARK: Writing

    private var writing: some View {
        VStack(spacing: 16) {
            // A vertical-axis TextField rather than a TextEditor. It grows the same way, but it
            // has a real prompt instead of an overlaid fake one, and it takes keyboard input
            // reliably under UI automation — a TextEditor here silently swallowed typed text,
            // which left the save button disabled and the whole suite red.
            TextField(
                "What is on your mind",
                text: $model.text,
                prompt: Text("Everything on your mind. One line each, or all in one go."),
                axis: .vertical
            )
            .font(.body)
            .lineLimit(5...12)
            .textInputAutocapitalization(.sentences)
            .padding(12)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
            .focused($isFieldFocused)
            .accessibilityIdentifier("capture-text-field")

            if let failure = model.failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("capture-failure")
            }

            Button {
                Task { await model.extract() }
            } label: {
                if model.isExtracting {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 52)
                } else {
                    Text("Sort this out")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("capture-extract-button")

            // Always present, never behind a menu. This is the path that works when nothing
            // else does, so it is not treated as the lesser option.
            Button("Just save it as one task") {
                Task { await model.saveAsSingleTask() }
            }
            .font(.subheadline)
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("capture-save-single-button")

            Spacer()
        }
        .padding(20)
        .onAppear { isFieldFocused = true }
    }

    // MARK: Saved

    private func saved(count: Int) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(count == 1 ? "Added." : "Added \(count) things.")
                .font(.title2.weight(.semibold))
            Text("NEXT will work out where to start.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("capture-done-button")
        }
        .padding(24)
        .accessibilityIdentifier("capture-saved")
    }
}
