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

    /// Drives the one place this screen has to bend at accessibility sizes — see `actionHeight`.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

            Spacer(minLength: 0)
        }
        .padding(20)
        // The actions live in a safe-area inset so they sit *above* the keyboard rather than
        // behind it. Capture is a screen the user is typing on the whole time they are on it;
        // making them dismiss the keyboard to reach Save would add a step to the one flow that
        // has to stay frictionless. It is also why the UI tests could not tap the button.
        .safeAreaInset(edge: .bottom) { actions }
        .onAppear { isFieldFocused = true }
    }

    /// The floor under the primary button, which is dropped once the text sets its own.
    ///
    /// 52 points is a comfortable target when the label is small. At an accessibility size the
    /// label is already taller than that, so the floor stops being a minimum and becomes dead
    /// space — and this bar sits above the keyboard on the one screen the user types on. The
    /// audit caught the consequence: at the largest size the save button stopped being reachable
    /// at all, which is `PRODUCT_SPEC.md` §11's "without destroying key screens" failing outright.
    private var actionHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 0 : 52
    }

    private var actions: some View {
        VStack(spacing: 10) {
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
                        .frame(maxWidth: .infinity, minHeight: actionHeight)
                } else {
                    Text("Sort this out")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: actionHeight)
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
            // Room for the words at any type size, and a fingertip-sized target around them.
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibleTapTarget()
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("capture-save-single-button")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Saved

    // Note: no accessibility identifier on the container. SwiftUI propagates a container's
    // identifier down to its children, which silently overwrote the Done button's own — the
    // button was on screen the whole time under the wrong name, and the UI suite spent several
    // CI runs failing as though saving had not worked.
    private func saved(count: Int) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(count == 1 ? "Added." : "Added \(count) things.")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("capture-saved")
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
    }
}
