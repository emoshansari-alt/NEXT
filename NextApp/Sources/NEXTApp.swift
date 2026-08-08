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

    private static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    private let repository: any TaskRepository
    private let onboarding: OnboardingState

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

        onboarding = OnboardingState()
        if Self.isUITesting { onboarding.reset() }
    }

    var body: some Scene {
        WindowGroup {
            RootView(onboarding: onboarding) { today }
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
            // Built on demand so each visit starts fresh rather than from whatever the last one
            // was abandoned mid-way through.
            makeCaptureModel: { CaptureViewModel(repository: repository) },
            makeEverythingModel: { EverythingViewModel(repository: repository) },
            makeDetailModel: { task in
                TaskDetailViewModel(task: task, repository: repository)
            },
            makeSettingsModel: { SettingsViewModel(repository: repository) }
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

    private static func makeContainer() -> (ModelContainer, Bool) {
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

    @ViewBuilder let today: () -> TodayView

    @State private var hasOnboarded: Bool

    init(onboarding: OnboardingState, @ViewBuilder today: @escaping () -> TodayView) {
        self.onboarding = onboarding
        self.today = today
        _hasOnboarded = State(initialValue: onboarding.hasCompleted)
    }

    var body: some View {
        if hasOnboarded {
            today()
        } else {
            OnboardingView {
                onboarding.markCompleted()
                hasOnboarded = true
            }
        }
    }
}
