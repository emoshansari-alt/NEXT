import NextKit
import SwiftUI

/// Everything — see it, fix it, close it again.
///
/// A plain grouped list. No board, no filters, no tags, no nested workspaces
/// (PRODUCT_SPEC.md §4.7). The sections come from `TaskSections` in `NextKit`, which is where
/// the calendar arithmetic is tested.
struct EverythingView: View {

    @State var model: EverythingViewModel
    var onOpenTask: (TaskItem) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.sections.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .navigationTitle("Everything")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("everything-close-button")
                }
            }
        }
        .task { await model.load() }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("Nothing captured yet.")
                .font(.title3.weight(.semibold))
            Text("Whatever is on your mind goes here first.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .accessibilityIdentifier("everything-empty")
    }

    private var list: some View {
        List {
            if let failure = model.storeFailure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("everything-failure")
            }

            section("Overdue", model.sections.overdue, id: "overdue")
            section("Today", model.sections.today, id: "today")
            section("Upcoming", model.sections.upcoming, id: "upcoming")
            section("No deadline", model.sections.undated, id: "undated")
            section("Completed", model.sections.completed, id: "completed")
            section("Archived", model.sections.archived, id: "archived")
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("everything-list")
    }

    @ViewBuilder
    private func section(_ title: String, _ tasks: [TaskItem], id: String) -> some View {
        if !tasks.isEmpty {
            Section {
                ForEach(tasks) { task in
                    row(task)
                }
            } header: {
                // The count is stated rather than left to be inferred from the list length —
                // a section header a screen reader announces as just "Overdue" is less useful
                // than one that says how much is in it.
                Text("\(title) · \(tasks.count)")
                    .accessibilityLabel("\(title), \(tasks.count) task\(tasks.count == 1 ? "" : "s")")
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        Button {
            onOpenTask(task)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.body)
                    .foregroundStyle(task.status == .active ? .primary : .secondary)
                    // Completion is never signalled by strikethrough or colour alone.
                    .strikethrough(task.status == .completed)

                if let detail = detailLine(task) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("task-row")
        .accessibilityLabel(accessibilityLabel(task))
        .accessibilityHint("Opens the task.")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await model.delete(task) }
            } label: {
                Label("Delete", systemImage: "trash")
            }

            if task.status == .active {
                Button {
                    Task { await model.complete(task) }
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.green)
            } else if task.status == .completed {
                Button {
                    Task { await model.reopen(task) }
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    private func detailLine(_ task: TaskItem) -> String? {
        var parts: [String] = []
        if let deadline = task.deadline {
            parts.append(deadline.formatted(date: .abbreviated, time: .omitted))
        }
        if let minutes = task.estimatedMinutes {
            parts.append("~\(minutes) min")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Status is spoken, never left to the strikethrough alone — meaning must not depend on a
    /// visual treatment a screen reader does not convey.
    private func accessibilityLabel(_ task: TaskItem) -> String {
        var parts = [task.title]
        switch task.status {
        case .completed: parts.append("Completed.")
        case .archived: parts.append("Archived.")
        case .active: break
        }
        if let detail = detailLine(task) { parts.append(detail) }
        return parts.joined(separator: " ")
    }
}
