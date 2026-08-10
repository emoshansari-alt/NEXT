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

    /// UI-test scaffolding: opens the recommendation as a linked task once, as a tapped
    /// notification would. See `NEXTApp.openRecommendedArgument` for why it exists.
    var opensRecommendedOnLaunch: Bool = false

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingRejectionReasons = false
    @State private var showingCapture = false
    @State private var showingEverything = false
    @State private var showingRescue = false
    @State private var showingMinimumWin = false

    var body: some View {
        ZStack {
            NextPalette.desk.ignoresSafeArea()

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
        // "Anything you do now will not be kept" is the single most important sentence this app
        // can say, and it appears at the very top of the screen — the one place VoiceOver has
        // already moved past by the time a store failure surfaces mid-session.
        .announcesFailure(warningText)
        .task {
            await model.load()
            await openRecommendedIfAsked()
        }
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
                    // Task Detail deliberately carries no Close button of its own, because it is
                    // normally *pushed* from Everything and the back button is the way out. Here
                    // it is the root of its own stack, so there is no back button — and a task
                    // opened from a tapped reminder or the widget could only be left by swiping
                    // the sheet down. A swipe is not an acceptable only way out of a screen.
                    //
                    // The control belongs to this wrapper rather than to Task Detail, so the
                    // pushed presentation does not grow a second, contradictory exit.
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { model.closeLinkedTask() }
                                .accessibilityIdentifier("linked-task-close-button")
                        }
                    }
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
            .font(NextType.meta)
            .foregroundStyle(NextPalette.warning)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, NextMetrics.screenPadding)
            .background(NextPalette.card)
            .accessibilityIdentifier("store-warning")
    }

    // MARK: Recommendation

    @ViewBuilder
    private func recommended(_ recommendation: Recommendation) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // The one card. There is deliberately never a second one on this screen — see
            // `CardSurface`, and DECISIONS.md D-023.
            VStack(alignment: .leading, spacing: 10) {
                Text("NEXT")
                    .nextEyebrow()
                    .accessibilityHidden(true)

                Text(recommendation.task.title)
                    .font(NextType.parent)
                    .foregroundStyle(NextPalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(recommendation.actionText)
                    .font(NextType.action)
                    .foregroundStyle(NextPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                // The marker: a stripe under the live action, never a fill behind it.
                Rectangle()
                    .fill(NextPalette.marker)
                    .frame(width: 44, height: 3)
                    .padding(.top, 2)
                    // Declared rather than left to a modifier interaction. A bare `Shape` is
                    // already absent from the accessibility tree, and the `.combine` below would
                    // absorb it in any case — but both of those are things that could change
                    // without anyone connecting the change to this stripe.
                    .accessibilityHidden(true)

                let copy = RecommendationCardCopy.lines(for: recommendation)

                if !copy.facts.isEmpty {
                    Text(copy.facts)
                        .font(NextType.meta)
                        .foregroundStyle(NextPalette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The answer to "why this one", on the card rather than behind a control.
                //
                // It appears only when the fact line above does not already carry it, which is
                // every reason that is not the deadline. `Why this?` used to be the only place
                // these sentences were shown, and a modal repeating the card the rest of the
                // time — so this is strictly more of the explanation, in fewer taps.
                if let reason = copy.reason {
                    Text(reason)
                        .font(NextType.meta)
                        .foregroundStyle(NextPalette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("recommendation-reason")
                }

                if recommendation.wasRecentlyRejected {
                    // Never silently re-serve something the user passed on.
                    Text(Self.recentlyRejectedNotice)
                        .font(NextType.meta)
                        .foregroundStyle(NextPalette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("recently-rejected-notice")
                }

                if recommendation.deadlineFeasibility.suggestsMinimumWin {
                    // A fact, not a warning and not a telling-off. The user already knows they
                    // are short of time; what they do not know is that there is still a version
                    // of this worth doing (PRODUCT_SPEC.md §4.12).
                    Text(Self.minimumWinNotice)
                        .font(NextType.meta)
                        .foregroundStyle(NextPalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("minimum-win-notice")
                }
            }
            .cardSurface()
            .padding(.horizontal, NextMetrics.screenPadding)
            // Read as one unit rather than six fragments when swiping through with VoiceOver.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(for: recommendation))
            // Deliberately *not* given an identifier of its own. A container's identifier
            // overwrites its children's, and `minimum-win-notice` and `recently-rejected-notice`
            // inside this card are both queried by tests. That is the collision `TESTING.md`
            // records losing CI rounds to; tests watching for a changed recommendation match on
            // the label instead.
            //
            // The single animated moment in the app: this card leaves, the next rises.
            .id(recommendation.task.id)
            .cardTransition()

            Spacer(minLength: 0)

            Button("START") {
                Task { await model.startRecommended() }
            }
            .buttonStyle(.primaryBlock)
            .padding(.horizontal, NextMetrics.screenPadding)
            .accessibilityIdentifier("start-button")
            .accessibilityHint("Opens Focus for this action.")

            secondaryActions()
                .padding(.top, 16)
                .padding(.bottom, 8)
        }
        .padding(.vertical, 28)
        // The reduce-aware curve, not the static spring. `cardTransition()` above already
        // substitutes a cross-fade for the movement; without this the timing would still be a
        // spring, so the card would fade with a bounce nobody asked for.
        .animation(NextMotion.cardChange(reduceMotion: reduceMotion), value: recommendation.task.id)
    }

    /// Two groups, and the grouping is the point.
    ///
    /// Everything that acts on **this recommendation** sits directly under START; the two ways out
    /// of the screen sit apart from it, at the bottom, in the plainer style. This is the layout
    /// `PRODUCT_SPEC.md` §4.2 has always described — the implementation had flattened it into one
    /// row of four peers, which at marketing scale read as four fragments of one undifferentiated
    /// set. They were never one set: two acted on the card, one navigated, one created.
    ///
    /// The separation is carried by position and by the underline the quiet style already owns,
    /// and by nothing else. A toolbar, an icon row or a menu here would each be a worse answer
    /// than the problem.
    private func secondaryActions() -> some View {
        VStack(spacing: 10) {
            // Only when the ladder genuinely exists. Offering "what can I still do?" for work
            // that comfortably fits would be manufacturing an emergency.
            if model.minimumWinPlan != nil {
                Button("What can I still do?") { showingMinimumWin = true }
                    .buttonStyle(.quietText)
                    .accessibilityIdentifier("minimum-win-button")
            }

            // This card. Two ways of saying the same thing for two different reasons — "I can't
            // do this" and "not this one" — so they belong beside each other, where somebody who
            // is already stuck is looking.
            HStack(spacing: 4) {
                Button("I'm stuck") { showingRescue = true }
                    .buttonStyle(.quietText)
                    .accessibilityIdentifier("im-stuck-button")

                Button("Something else") { showingRejectionReasons = true }
                    .buttonStyle(.quietText)
                    .accessibilityIdentifier("something-else-button")
            }

            // The app. Plainer and further away, because leaving this screen is not one of the
            // answers to the question it is asking.
            HStack(spacing: 4) {
                Button("Everything") { showingEverything = true }
                    .buttonStyle(.quietTextPlain)
                    .accessibilityIdentifier("everything-button")

                Button("Add") { showingCapture = true }
                    .buttonStyle(.quietTextPlain)
                    .accessibilityIdentifier("add-button")
            }
            .padding(.top, 2)
        }
    }

    /// Said once each, so the screen and the spoken label cannot drift apart.
    static let recentlyRejectedNotice = "You passed on this earlier, but it is what is left."
    static let minimumWinNotice = "There is not enough time left to finish this."

    private func accessibilityLabel(for recommendation: Recommendation) -> String {
        var parts = [recommendation.task.title, recommendation.actionText]
        parts.append(recommendation.explanation.sentence)
        if let minutes = recommendation.task.estimatedMinutes {
            parts.append("About \(minutes) minutes.")
        }
        // The card is read as one element, so anything not named here is not merely quieter —
        // it is inaudible. Both of these are the screen explaining itself, which is exactly the
        // part a sighted user gets for free and a VoiceOver user only gets if it is said.
        if recommendation.wasRecentlyRejected {
            parts.append(Self.recentlyRejectedNotice)
        }
        if recommendation.deadlineFeasibility.suggestsMinimumWin {
            parts.append(Self.minimumWinNotice)
        }
        return parts.joined(separator: " ")
    }

    // MARK: Empty states

    /// Every empty state offers the way out of it.
    ///
    /// A first run has nothing to recommend, and a screen that only says so is a dead end. The
    /// button is the whole point of the state, not a footnote to it.
    private func empty(headline: String, detail: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("NEXT")
                    .nextEyebrow()
                    .accessibilityHidden(true)

                Text(headline)
                    .font(NextType.heading)
                    .foregroundStyle(NextPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(NextType.body)
                    .foregroundStyle(NextPalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // An empty state is still the one card. The screen does not change shape because
            // there is nothing to do — it says so on the same object.
            .cardSurface(spine: false)
            .padding(.horizontal, NextMetrics.screenPadding)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("empty-state")

            Spacer()

            Button("Add something") { showingCapture = true }
                .buttonStyle(.primaryBlock)
                .padding(.horizontal, NextMetrics.screenPadding)
                .accessibilityIdentifier("empty-add-button")

            // Reachable even with nothing outstanding — otherwise completed and archived work
            // would be unreachable the moment the last task is done.
            Button("Everything") { showingEverything = true }
                .buttonStyle(.quietText)
                .padding(.top, 12)
                .accessibilityIdentifier("everything-button")
        }
        .padding(.vertical, 28)
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

    /// Goes through the same `open(_:)` a tapped reminder does, so the sheet under test is the
    /// real one. Does nothing outside UI testing — `opensRecommendedOnLaunch` is only ever true
    /// when `NEXTApp` was launched with both `-ui-testing` and `-ui-open-recommended`.
    private func openRecommendedIfAsked() async {
        guard opensRecommendedOnLaunch, let id = model.recommendation?.task.id else { return }
        await model.open(.task(id))
    }

    private var focusBinding: Binding<FocusTarget?> {
        Binding(
            get: { model.focus },
            set: { if $0 == nil { model.stopFocus() } }
        )
    }
}

/// Labels for the five "Something else" reasons. Each is about circumstance, never about the
/// user.
///
/// `.other` reads "Another reason" rather than "Something else", which is what it said until the
/// control above it took that name. A button and one of the options it opens cannot share a
/// label — the user would tap "Something else" and be offered "Something else".
enum RejectionCopy {
    static func label(for reason: RejectionReason) -> String {
        switch reason {
        case .cantRightNow: "Can't do it right now"
        case .missingWhatINeed: "Don't have what I need"
        case .needSomethingShorter: "Need something shorter"
        case .needLessEffort: "Need less effort"
        case .other: "Another reason"
        }
    }
}
