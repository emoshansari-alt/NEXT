import NextKit
import SwiftData
import SwiftUI

/// NEXT — know what to do next.
///
/// The app layer is deliberately thin. Every decision about *what* the user should do lives in
/// `NextKit`, which has no Apple UI dependency and is unit-tested off-device
/// (ARCHITECTURE.md §1). These views render that decision and send intents back.
@main
struct NEXTApp: App {

    /// Set by the UI test target so each run starts from a clean store and a fresh first run.
    ///
    /// Without it the UI tests would share the simulator's real database: the golden-path test
    /// completes a task, that completion persists, and after enough runs there is nothing left
    /// to recommend. A test that depends on how many times it has run before is not a test.
    static let uiTestingArgument = "-ui-testing"

    /// Seeds one task whose deadline is genuinely out of reach, so the Minimum Win flow can be
    /// driven end to end by a UI test.
    ///
    /// Scaffolding, and confined to it: it does nothing unless `-ui-testing` is also present, so
    /// it cannot affect a real run. It exists because Minimum Win needs a deadline that is close
    /// *but not passed* together with an estimate that does not fit — and Task Detail's date
    /// picker defaults to the current instant, which leaves no window at all. Driving a
    /// `DatePicker` to a specific future time through XCUITest is both fiddly and flaky, and a
    /// flaky test of a real flow is worse than an honest fixture for it.
    static let seedUnreachableArgument = "-ui-seed-unreachable"

    /// Followed by a name, seeds one realistic task so a captured screenshot shows a populated
    /// screen rather than a first run.
    ///
    /// Only the *data* is a fixture. Every pixel above it is the shipping interface rendering that
    /// data the way it would render anything else, which is the line `DECISIONS.md` D-024 draws:
    /// marketing may not fabricate functionality, and a task a student could plausibly have typed
    /// is not fabricated functionality. Typing the same task through Capture would leave it with
    /// no deadline and no estimate, so the meta line would be empty — a less honest picture of the
    /// app, not a more honest one.
    ///
    /// `essay` is due in two days and drives the recommendation, Focus and Why-this screens.
    /// `overdue` is two days late, which is the one state no competitor screenshots and the whole
    /// point of the last frame.
    static let seedArgument = "-ui-seed"

    /// Followed by `light` or `dark`, presets the appearance the Settings picker controls.
    ///
    /// Test scaffolding for one job: capturing the App Store set's dark frame from the feature
    /// the listing advertises. Two earlier attempts drove the *simulator's* appearance instead
    /// and silently produced a light screenshot, which is a marketing claim the app would not
    /// have kept.
    static let appearanceArgument = "-ui-appearance"

    /// Opens whatever Today is recommending as though a notification or the widget had been
    /// tapped, so the deep-link sheet can be reached from a UI test.
    ///
    /// Scaffolding, and gated on `-ui-testing` like the rest. It exists because that sheet is
    /// otherwise only reachable through a real `next://` URL, and the only way to deliver one to
    /// the app under XCUITest is to drive Safari — which is slow, flaky in CI, and would be
    /// testing Safari's address bar as much as NEXT. The same trade the unreachable-deadline
    /// seed above already makes: an honest fixture beats a flaky test of the real path.
    ///
    /// What it does *not* fake is the thing under test. The sheet, its wrapper and its Close
    /// button are the real ones; only the tap that opens it is simulated.
    static let openRecommendedArgument = "-ui-open-recommended"

    /// Followed by a name, this puts the UI-testing store on **disk** instead of in memory, in a
    /// throwaway location of its own.
    ///
    /// It exists for the one thing an in-memory store makes impossible to check: that work
    /// survives the app being killed. `-ui-testing` deliberately swaps in a fresh container per
    /// launch so the golden path cannot eat its own fixtures — which is right for every other
    /// test and fatal for this one, because "relaunch and verify" against a store that is
    /// recreated on launch would pass no matter what the persistence layer did.
    ///
    /// The name scopes the file, so a test owns its own database and two tests cannot interfere.
    static let storeNameArgument = "-ui-store-name"

    /// Deletes that store before opening it. Passed on a test's *first* launch only — the whole
    /// point of the later ones is to find what the earlier ones left behind.
    static let resetStoreArgument = "-ui-reset-store"

    private static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    private static var shouldSeedUnreachable: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains(seedUnreachableArgument)
    }

    private static var shouldOpenRecommended: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains(openRecommendedArgument)
    }

    /// The appearance given after `-ui-appearance`, or `nil`.
    private static var forcedAppearance: AppearancePreference? {
        guard isUITesting else { return nil }

        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: appearanceArgument),
              case let next = arguments.index(after: flag),
              next < arguments.endIndex
        else { return nil }

        return AppearancePreference(rawValue: arguments[next])
    }

    /// The name given after `-ui-seed`, or `nil`.
    private static var seedName: String? {
        guard isUITesting else { return nil }

        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: seedArgument),
              case let next = arguments.index(after: flag),
              next < arguments.endIndex
        else { return nil }

        return arguments[next]
    }

    /// Where a named UI-testing store lives, or `nil` for the ordinary in-memory one.
    ///
    /// Under the temporary directory rather than Application Support: it is scratch data owned by
    /// a test run, and putting it where the real store lives would risk a test clearing something
    /// that is not its own.
    private static var uiTestingStoreURL: URL? {
        guard isUITesting else { return nil }

        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: storeNameArgument),
              case let next = arguments.index(after: flag),
              next < arguments.endIndex
        else { return nil }

        let name = arguments[next]
        // A name is used to build a path, so anything that could climb out of the directory is
        // refused rather than sanitised — this is test scaffolding and a silently rewritten path
        // would be worse than a clear refusal.
        guard !name.isEmpty, !name.contains("/"), !name.contains("."), name != ".." else {
            return nil
        }

        return FileManager.default.temporaryDirectory
            .appendingPathComponent("next-ui-\(name).store")
    }

    private let repository: any TaskRepository
    private let onboarding: OnboardingState

    /// The user's chosen appearance. Owned here because `preferredColorScheme` only takes effect
    /// at the scene root, and Settings — where it is chosen — is a sheet well below it.
    private let appearance: AppearanceState

    /// Finishes transactions that arrive from outside a purchase — renewals, an Ask to Buy
    /// approval that lands days later, a purchase made on another device. An unfinished
    /// transaction is re-delivered indefinitely, so this has to run for the life of the app and
    /// not only while a paywall is on screen.
    private let transactions = StoreKitTransactionListener()

    /// Where a tapped notification is parked until Today is ready to act on it.
    private let inbox = DeepLinkInbox()

    /// Turns a tapped reminder into a destination. Held for the life of the app because
    /// `UNUserNotificationCenter` keeps only a weak reference to its delegate.
    private let notifications: NotificationRouter

    /// True when the disk store could not be opened and the app is running on a throwaway
    /// in-memory one.
    private let storeIsEphemeral: Bool

    init() {
        // A container that will not open is not a reason to crash on launch — but it is
        // absolutely a reason to tell the user. Falling back to an in-memory store keeps the
        // app usable for this session; the banner keeps it honest that nothing written now will
        // still be there tomorrow. Silently swapping in an empty store would let a student
        // believe their work had been deleted.
        let (container, isEphemeral) = Self.makeContainer()
        repository = SwiftDataTaskRepository(modelContainer: container)
        storeIsEphemeral = isEphemeral

        // Written straight into the container rather than through the repository, because the
        // repository is an actor and the first screen reads as soon as it appears — an awaited
        // seed would race the read it exists to satisfy.
        if Self.shouldSeedUnreachable { Self.seedUnreachableTask(into: container) }
        if let seed = Self.seedName { Self.seed(seed, into: container) }

        onboarding = OnboardingState()
        if Self.isUITesting { onboarding.reset() }

        appearance = AppearanceState()
        if Self.isUITesting {
            // The preference lives in the real `UserDefaults`, which `-ui-testing` does not
            // reset, so one test turning dark mode on would otherwise change the appearance of
            // every test that runs after it. Reset to light unless the launch says otherwise.
            //
            // The cost is that a UI test cannot observe the preference surviving a relaunch —
            // this reset is indistinguishable from having forgotten it. Persistence is proven at
            // the unit level instead (`theChoiceIsPersistedAsItIsMade`), which is the honest
            // division: the harness owns the starting state, so the harness cannot also be the
            // witness that the state was kept.
            appearance.preference = Self.forcedAppearance ?? .light
        }

        notifications = NotificationRouter(inbox: inbox)
        notifications.start()
    }

    var body: some Scene {
        WindowGroup {
            // The appearance is applied inside `RootView`, not here. `@Observable` tracking is
            // not reliable in an `App` body: reading `appearance.preference` at this level meant
            // flipping the switch never re-rendered the root, and three different ways of
            // applying it all measured the same brightness to sixteen digits — which is what
            // "never re-rendered" looks like from the outside.
            RootView(onboarding: onboarding, appearance: appearance) { today }
                // One accent, set once. Every system control — pickers, switches, the navigation
                // bar's own buttons — inherits it, so ballpoint blue is the only accent in the app
                // without each screen having to say so.
                .tint(NextPalette.biro)
                // Started here rather than in `init` so it is unambiguously on the main actor.
                // Starting twice is a no-op, which is what makes that safe.
                .task { transactions.start() }
        }
    }

    private var today: TodayView {
        TodayView(
            model: TodayViewModel(
                repository: repository,
                snapshotPublisher: SnapshotPublisher(),
                // Reminders are planned from the whole list, so a completion has to cancel its
                // own reminder. Without this NEXT would notify someone about work they finished
                // this morning.
                onStoreChanged: { await Self.rescheduleReminders(repository: repository) }
            ),
            storeIsEphemeral: storeIsEphemeral,
            opensRecommendedOnLaunch: Self.shouldOpenRecommended,
            // Built on demand so each visit starts fresh rather than from whatever the last one
            // was abandoned mid-way through.
            makeCaptureModel: { CaptureViewModel(repository: repository) },
            makeEverythingModel: { EverythingViewModel(repository: repository) },
            makeDetailModel: { task in
                TaskDetailViewModel(task: task, repository: repository)
            },
            makeSettingsModel: { SettingsViewModel(repository: repository, appearance: appearance) },
            inbox: inbox
        )
    }

    /// Re-plans and re-schedules every reminder from the current task list.
    ///
    /// Silently does nothing when the user has not granted permission, which is the correct
    /// outcome rather than an error: they said no, and the app's job is to respect that without
    /// making a fuss about it every time a task changes.
    private static func rescheduleReminders(repository: any TaskRepository) async {
        let scheduler = SystemNotificationScheduler()
        guard await scheduler.authorizationStatus() == .authorized else { return }

        let store = AppSettingsStore()
        guard let tasks = try? await repository.fetchAll() else { return }

        let reminders = ReminderPlanner.reminders(
            for: tasks,
            preferences: store.reminderPreferences,
            now: Date(),
            calendar: .current
        )
        await scheduler.replacePending(with: reminders)
    }

    /// Three hours of work due in forty-five minutes: unreachable, with a window still open.
    ///
    /// Both halves matter. Without the estimate the planner correctly declines to invent a
    /// ladder out of a duration nobody recorded; with the deadline already passed there is no
    /// window to fit anything into and it correctly declines again.
    private static func seedUnreachableTask(into container: ModelContainer) {
        let context = ModelContext(container)
        context.insert(
            StoredTask(
                task: TaskItem(
                    id: TaskID("ui-unreachable-essay"),
                    title: "History essay",
                    createdAt: Date(),
                    deadline: Date().addingTimeInterval(45 * 60),
                    estimatedMinutes: 180
                )
            )
        )
        try? context.save()
    }

    /// One named task, written straight into the container for the same reason the unreachable
    /// seed is: the first screen reads as soon as it appears, and an awaited write would race it.
    private static func seed(_ name: String, into container: ModelContainer) {
        let now = Date()
        let task: TaskItem?

        switch name {
        case "essay":
            task = TaskItem(
                id: TaskID("ui-seed-essay"),
                title: "History essay",
                createdAt: now,
                deadline: now.addingTimeInterval(2 * 24 * 3600),
                estimatedMinutes: 20,
                nextAction: "Find three sources."
            )

        case "overdue":
            task = TaskItem(
                id: TaskID("ui-seed-overdue"),
                title: "Chemistry worksheet",
                createdAt: now.addingTimeInterval(-6 * 24 * 3600),
                deadline: now.addingTimeInterval(-2 * 24 * 3600),
                estimatedMinutes: 25,
                nextAction: "Do questions 1 to 5."
            )

        default:
            // An unrecognised name seeds nothing rather than guessing. A screenshot of the wrong
            // state is worse than a screenshot of an empty one, because it is not obviously wrong.
            task = nil
        }

        guard let task else { return }

        let context = ModelContext(container)
        context.insert(StoredTask(task: task))
        try? context.save()
    }

    private static func makeContainer() -> (ModelContainer, Bool) {
        if let url = uiTestingStoreURL {
            if ProcessInfo.processInfo.arguments.contains(resetStoreArgument) {
                // The write-ahead log and shared-memory files sit beside the database. Deleting
                // only the database and leaving a stale journal next to it is how a run that is
                // supposed to start clean starts dirty instead.
                for suffix in ["", "-wal", "-shm"] {
                    try? FileManager.default.removeItem(atPath: url.path + suffix)
                }
            }

            do {
                return (
                    try ModelContainer(
                        for: StoredTask.self,
                        migrationPlan: NextMigrationPlan.self,
                        configurations: ModelConfiguration(url: url)
                    ),
                    false
                )
            } catch {
                fatalError("NEXT could not open the UI-testing store at \(url): \(error)")
            }
        }

        if isUITesting {
            do {
                return (
                    try ModelContainer(
                        for: StoredTask.self,
                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                    ),
                    // Not flagged as a warning: ephemeral is exactly what was asked for, so the
                    // banner would appear in every UI test.
                    false
                )
            } catch {
                fatalError("NEXT could not create an in-memory store for UI testing: \(error)")
            }
        }

        do {
            return (
                try ModelContainer(for: StoredTask.self, migrationPlan: NextMigrationPlan.self),
                false
            )
        } catch {
            do {
                return (
                    try ModelContainer(
                        for: StoredTask.self,
                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                    ),
                    true
                )
            } catch {
                // An in-memory container failing means SwiftData itself cannot start. There is
                // no degraded mode left to offer.
                fatalError("NEXT could not create any task store: \(error)")
            }
        }
    }
}

/// Onboarding, then the app.
///
/// Split out so the decision is one piece of state in one place, rather than a condition
/// threaded through the scene body.
struct RootView: View {

    let onboarding: OnboardingState

    /// Read here rather than in `NEXTApp.body`, so the observation actually tracks.
    let appearance: AppearanceState

    @ViewBuilder let today: () -> TodayView

    @State private var hasOnboarded: Bool

    init(
        onboarding: OnboardingState,
        appearance: AppearanceState,
        @ViewBuilder today: @escaping () -> TodayView
    ) {
        self.onboarding = onboarding
        self.appearance = appearance
        self.today = today
        _hasOnboarded = State(initialValue: onboarding.hasCompleted)
    }

    var body: some View {
        Group {
            if hasOnboarded {
                today()
            } else {
                OnboardingView {
                    onboarding.markCompleted()
                    hasOnboarded = true
                }
            }
        }
        // Only while the switch is reachable. Until then NEXT follows the phone, which is what
        // it did before this feature and is a working behaviour rather than a broken one.
        .appearance(AppearanceAvailability.isDarkModeReachable ? appearance.preference : nil)
    }
}
