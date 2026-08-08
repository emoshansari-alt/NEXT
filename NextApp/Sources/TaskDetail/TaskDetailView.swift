import NextKit
import SwiftUI

/// Task Detail. Everything about one task, and the ways to change it.
///
/// Priority is two values, not five (PRODUCT_SPEC.md §4.8): every extra level is a decision the
/// user has to make, and P1 says reduce decisions rather than create them.
struct TaskDetailView: View {

    @State var model: TaskDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteConfirmation = false

    private static let durations: [Int?] = [nil, 5, 15, 30, 45, 60, 120]

    // No NavigationStack of its own: this is pushed onto Everything's, and nesting one inside
    // another breaks the back button and the toolbar placement.
    var body: some View {
        Group {
            Form {
                if let failure = model.failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("detail-failure")
                }

                Section("Task") {
                    TextField("Task", text: $model.title, axis: .vertical)
                        .accessibilityIdentifier("detail-title-field")
                        .accessibilityLabel("Task name")

                    TextField("Notes", text: $model.notes, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityIdentifier("detail-notes-field")
                        .accessibilityLabel("Notes")
                }

                Section("First step") {
                    TextField("What is the first thing to do?", text: $model.nextAction, axis: .vertical)
                        .accessibilityIdentifier("detail-next-action-field")
                        .accessibilityLabel("First step")
                }

                Section("When") {
                    deadlineControls
                }

                Section("How long") {
                    Picker("Estimate", selection: $model.estimatedMinutes) {
                        ForEach(Self.durations, id: \.self) { minutes in
                            Text(minutes.map { "\($0) min" } ?? "Not sure")
                                .tag(minutes)
                        }
                    }
                    .accessibilityIdentifier("detail-estimate-picker")
                }

                Section("Priority") {
                    Picker("Priority", selection: $model.importance) {
                        Text("Normal").tag(Importance.normal)
                        Text("Important").tag(Importance.important)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("detail-importance-picker")
                }

                actions
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            // No Close button: this is a pushed screen, so the navigation bar's back button is
            // the way out. Adding a second one would be two controls doing the same job.
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await model.save() } }
                        .disabled(!model.canSave)
                        .accessibilityIdentifier("detail-save-button")
                }
            }
            .confirmationDialog(
                "Delete this task?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        await model.delete()
                        if model.isDeleted { dismiss() }
                    }
                }
                Button("Keep it", role: .cancel) {}
            } message: {
                // Stated plainly. There is no server copy and nothing to restore from.
                Text("This cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private var deadlineControls: some View {
        Toggle(
            "Has a deadline",
            isOn: Binding(
                get: { model.deadline != nil },
                set: { model.deadline = $0 ? (model.deadline ?? Date()) : nil }
            )
        )
        .accessibilityIdentifier("detail-deadline-toggle")

        if let deadline = model.deadline {
            DatePicker(
                "Due",
                selection: Binding(get: { deadline }, set: { model.deadline = $0 }),
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("detail-deadline-picker")
        }
    }

    @ViewBuilder
    private var actions: some View {
        Section {
            switch model.task.status {
            case .active:
                Button("Mark done") { Task { await model.complete() } }
                    .accessibilityIdentifier("detail-complete-button")
                Button("Archive") { Task { await model.archive() } }
                    .accessibilityIdentifier("detail-archive-button")
            case .completed:
                Button("Reopen") { Task { await model.reopen() } }
                    .accessibilityIdentifier("detail-reopen-button")
                Button("Archive") { Task { await model.archive() } }
                    .accessibilityIdentifier("detail-archive-button")
            case .archived:
                Button("Reopen") { Task { await model.reopen() } }
                    .accessibilityIdentifier("detail-reopen-button")
            }
        }

        Section {
            Button("Delete", role: .destructive) { showingDeleteConfirmation = true }
                .accessibilityIdentifier("detail-delete-button")
        }
    }
}
