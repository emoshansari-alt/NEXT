import NextKit
import SwiftUI

/// The primary screen. One recommendation, one obvious action.
///
/// The dominant object on screen is the thing to do. There is no dashboard, no list competing
/// for attention, and no metric tiles — PRODUCT_SPEC.md §4.2. Every layout decision here is in
/// service of making the next action obvious.
struct TodayView: View {

    @State var model: TodayViewModel

    /// Set when the app is running on a throwaway store. Shown, never hidden.
    var storeIsEphemeral: Bool = false

    /// Builds the capture screen's model. Injected so tests can supply an in-memory store and a
    /// fixed clock instead of the app's real ones.
    var makeCaptureModel: () -> CaptureViewModel

    /// Builds the Everything screen's model. Same reasoning.
    var makeEverythingModel: () -> EverythingViewModel

    /// Builds Task Detail for one task.
    var makeDetailModel: (TaskItem) -> TaskDetailViewModel

    /// Builds Settings, reached from Everything.
    var makeSettingsModel: () -> SettingsViewModel

    /// Where a tapped notification is left. `nil` in tests that do not exercise it.
    ///
    /// Parked rather than delivered directly because a notification can arrive before this screen
    /// exists — a cold launch from the lock screen is exactly that — so there may be nothing
    /// listening at the moment iOS hands the tap over.
    var inbox: DeepLinkInbox?

    @State private var showingRejectionReasons = false
    @State private var showingExplanation = false
    @State private var showingCapture = false
    @State private var showingEverything = false
    @State private var showingRescue = false
    @State private var showingMinimumWin = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                if let warning = warningText {
                    banner(warning)
                }

                switch model.outcome {
                case .recommended(let recommendation):
                    recommended(recommendation)
                case .nothingToDo:
                    empty(
                        headline: UnavailabilityCopy.emptyHeadline,
                        detail: UnavailabilityCopy.emptyDetail
                    )
                case .nothingAvailable(let reason):
                    empty(
                        headline: UnavailabilityCopy.headline(for: reason),
                        detail: UnavailabilityCopy.detail(for: reason)
                    )
                }
            }
        }
        .task { await model.load() }
        .onOpenURL { url in
            // Unrecognised links are ignored rather than guessed at — opening the wrong task
            // because a URL nearly matched would be worse than doing nothing.
            guard let link = DeepLink(url: url) else { return }
            Task { await model.open(link) }
        }
        // A notification tapped while the app was not running lands here, once. Taken rather than
        // read, so it cannot be acted on twice if this view is rebuilt.
        .task { await openPendingLink() }
        .onChange(of: inbox?.pending) { _, _ in
            Task { await openPendingLink() }
        }
        .sheet(
            item: Binding(
                get: { model.linkedTask },
                set: { if $0 == nil { model.closeLinkedTask() } }
            ),
            onDismiss: { Task { await model.load() } }
        ) { task in
            NavigationStack {
                TaskDetailView(model: makeDetailModel(task))
            }
        }
        // Every sheet reloads on dismiss. Any of them can change the store, and Today showing a
        // recommendation for a task that was just deleted or completed elsewhere would be worse
        // than a moment's delay.
        .sheet(isPresented: $showingCapture, onDismiss: { Task { await model.load() } }) {
            CaptureView(model: makeCaptureModel())
        }
        .sheet(isPresented: $showingEverything, onDismiss: { Task { await model.load() } }) {
            EverythingView(
                model: makeEverythingModel(),
                makeDetailModel: makeDetailModel,
                makeSettingsModel: makeSettingsModel
            )
        }
        .sheet(isPresented: $showingRescue) {
            if let task = model.recommendation?.task {
                RescueView(
                    task: task,
                    allTasks: model.tasks,
                    onStart: { response in
                        // Focus on the step Rescue offered, not on the task it came from. The
                        // response also names its own task, which the "not enough time" path can
                        // change by re-ranking — so the model resolves it rather than assuming.
                        Task { await model.focusRescued(response) }
                    }
                )
            }
        }
        .sheet(isPresented: $showingMinimumWin) {
            if let plan = model.minimumWinPlan {
                MinimumWinView(
                    plan: plan,
                    onChoose: { rung in
                        Task { await model.focusMinimumWin(rung, in: plan) }
                    }
                )
            }
        }
        .fullScreenCover(item: focusBinding) { target in
            FocusView(
                target: target,
                allTasks: model.tasks,
                onDone: { Task { await model.completeFocused() } },
                onStop: { model.stopFocus() },
                // Being stuck happens while working. Rescue answers from inside Focus and the
                // smaller step replaces the action in place, so the session continues rather than
                // bouncing the user back to Today and making them start again.
                onRescued: { response in Task { await model.focusRescued(response) } }
            )
        }
        .confirmationDialog(
            "Why not this one?",
            isPresented: $showingRejectionReasons,
            titleVisibility: .visible
        ) {
            ForEach(RejectionReason.allCases, id: \.self) { reason in
                Button(RejectionCopy.label(for: reason)) {
                    Task { await model.rejectRecommended(reason: reason) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Warnings

    /// Storage problems are stated plainly and never dressed up. A student who cannot see that
    /// their work is not being saved will assume it is.
    private var warningText: String? {
        if let failure = model.storeFailure { return failure }
        if storeIsEphemeral { return "Saving is unavailable. Anything you do now will not be kept." }
        return nil
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(Color(.secondarySystemBackground))
            .accessibilityIdentifier("store-warning")
    }

    // MARK: Recommendation

    @ViewBuilder
    private func recommended(_ recommendation: Recommendation) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Text("NEXT")
                    .font(.footnote.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(recommendation.task.title)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(recommendation.actionText)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)

                if !metaLine(for: recommendation).isEmpty {
                    Text(metaLine(for: recommendation))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if recommendation.wasRecentlyRejected {
                    // Never silently re-serve something the user passed on.
                    Text("You passed on this earlier, but it is what is left.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if recommendation.deadlineFeasibility.suggestsMinimumWin {
                    // A fact, not a warning and not a telling-off. The user already knows they
                    // are short of time; what they do not know is that there is still a version
                    // of this worth doing (PRODUCT_SPEC.md §4.12).
                    Text("There is not enough time left to finish this.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("minimum-win-notice")
                }
            }
            .padding(.horizontal, 28)
            // Read as one unit rather than four fragments when swiping through with VoiceOver.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(for: recommendation))

            Spacer(minLength: 0)

            Button {
                Task { await model.startRecommended() }
            } label: {
                Text("START")
                    .font(.headline)
                    .tracking(1)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .accessibilityIdentifier("start-button")
            .accessibilityHint("Opens Focus for this action.")

            secondaryActions(recommendation)
                .padding(.top, 20)
                .padding(.bottom, 12)
        }
        .padding(.vertical, 32)
    }

    private func secondaryActions(_ recommendation: Recommendation) -> some View {
        VStack(spacing: 14) {
            // Only when the ladder genuinely exists. Offering "what can I still do?" for work
            // that comfortably fits would be manufacturing an emergency.
            if model.minimumWinPlan != nil {
                Button("What can I still do?") { showingMinimumWin = true }
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("minimum-win-button")
            }

            // "I'm stuck" sits on its own line and reads first. It is a first-class feature,
            // not a footnote — the moment someone needs it is the moment they are least likely
            // to go hunting for it.
            Button("I'm stuck") { showingRescue = true }
                .font(.subheadline.weight(.medium))
                .accessibleTapTarget()
                .accessibilityIdentifier("im-stuck-button")

            HStack(spacing: 22) {
                Button("Not this") { showingRejectionReasons = true }
                    .accessibleTapTarget()
                    .accessibilityIdentifier("not-this-button")

                Button("Why this?") { showingExplanation = true }
                    .accessibleTapTarget()
                    .accessibilityIdentifier("why-this-button")

                Button("Everything") { showingEverything = true }
                    .accessibleTapTarget()
                    .accessibilityIdentifier("everything-button")

                Button("Add") { showingCapture = true }
                    .accessibleTapTarget()
                    .accessibilityIdentifier("add-button")
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .alert(
            "Why this?",
            isPresented: $showingExplanation,
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(recommendation.explanation.sentence) }
        )
    }

    /// "Due in 2 days · ~20 min", assembled from whatever the task actually knows.
    /// Uses a middle dot rather than colour or an icon to separate facts, because meaning must
    /// never depend on colour alone.
    private func metaLine(for recommendation: Recommendation) -> String {
        var parts: [String] = []

        if recommendation.task.deadline != nil {
            parts.append(
                recommendation.explanation.sentence.replacingOccurrences(of: ".", with: "")
            )
        }
        if let minutes = recommendation.task.estimatedMinutes {
            parts.append("~\(minutes) min")
        }
        return parts.joined(separator: " · ")
    }

    private func accessibilityLabel(for recommendation: Recommendation) -> String {
        var parts = [recommendation.task.title, recommendation.actionText]
        parts.append(recommendation.explanation.sentence)
        if let minutes = recommendation.task.estimatedMinutes {
            parts.append("About \(minutes) minutes.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Empty states

    /// Every empty state offers the way out of it.
    ///
    /// A first run has nothing to recommend, and a screen that only says so is a dead end. The
    /// button is the whole point of the state, not a footnote to it.
    private func empty(headline: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Spacer()

            VStack(spacing: 10) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("empty-state")

            Spacer()

            Button {
                showingCapture = true
            } label: {
                Text("Add something")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("empty-add-button")

            // Reachable even with nothing outstanding — otherwise completed and archived work
            // would be unreachable the moment the last task is done.
            Button("Everything") { showingEverything = true }
                .font(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibleTapTarget()
                .accessibilityIdentifier("everything-button")
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }

    // MARK: Focus presentation

    /// Acts on a parked notification tap, if there is one.
    ///
    /// Routed through the identical `model.open` the widget's URLs use, so a reminder and a widget
    /// arrive by one path — including the handling of a link to a task that has since been
    /// deleted, which leaves the user on Today rather than erroring.
    private func openPendingLink() async {
        guard let link = inbox?.take() else { return }
        await model.open(link)
    }

    private var focusBinding: Binding<FocusTarget?> {
        Binding(
            get: { model.focus },
            set: { if $0 == nil { model.stopFocus() } }
        )
    }
}

/// Labels for the five "Not this" reasons. Each is about circumstance, never about the user.
enum RejectionCopy {
    static func label(for reason: RejectionReason) -> String {
        switch reason {
        case .cantRightNow: "Can't do it right now"
        case .missingWhatINeed: "Don't have what I need"
        case .needSomethingShorter: "Need something shorter"
        case .needLessEffort: "Need less effort"
        case .other: "Something else"
        }
    }
}
