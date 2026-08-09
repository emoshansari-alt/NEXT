import SwiftUI

/// Onboarding. Three screens, then the app.
///
/// PRODUCT_SPEC.md §4.1 is emphatic about what is *not* here: no account, no email, no username,
/// no profile, no school, no major, no age survey, no productivity quiz, no personalisation
/// questionnaire. Nothing is asked because nothing is needed — the user reaches useful
/// functionality in three taps, and the app has no identity to attach to them.
///
/// Permissions are not requested here either. They are asked for contextually, at the moment
/// they are actually needed, rather than as a wall of prompts before the user knows what the app
/// even does.
struct OnboardingView: View {

    let onFinish: () -> Void

    @State private var page = 0

    private struct Panel: Identifiable {
        let id: Int
        let headline: String
        let body: String?
    }

    private let panels = [
        Panel(id: 0, headline: "Too much to do?", body: "Put it here."),
        Panel(id: 1, headline: "NEXT figures out what deserves your attention.", body: nil),
        Panel(id: 2, headline: "You only have to start one thing.", body: "The next thing.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(panels) { panel in
                    panelView(panel).tag(panel.id)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < panels.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < panels.count - 1 ? "Next" : "Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .accessibilityIdentifier("onboarding-continue-button")

            // Always available. Three screens is short, but nobody should be made to sit
            // through an introduction to reach an app they have already decided to use.
            Button("Skip") { onFinish() }
                .font(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibleTapTarget()
                .padding(.top, 14)
                .padding(.bottom, 28)
                .accessibilityIdentifier("onboarding-skip-button")
        }
        .background(Color(.systemBackground))
    }

    private func panelView(_ panel: Panel) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Text(panel.headline)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)

            if let body = panel.body {
                Text(body)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([panel.headline, panel.body].compactMap { $0 }.joined(separator: " "))
    }
}

/// Whether onboarding has been seen.
///
/// `UserDefaults` rather than the task store: it is a preference about the app, not the user's
/// work, and it should not travel with a task database or complicate a schema migration.
struct OnboardingState {

    private static let key = "next.hasCompletedOnboarding"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasCompleted: Bool {
        defaults.bool(forKey: Self.key)
    }

    func markCompleted() {
        defaults.set(true, forKey: Self.key)
    }

    /// Used by UI tests, which need a predictable first run every launch.
    func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}
