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

    private let repository: any TaskRepository

    /// True when the disk store could not be opened and the app is running on a throwaway
    /// in-memory one.
    private let storeIsEphemeral: Bool

    init() {
        // A container that will not open is not a reason to crash on launch — but it is
        // absolutely a reason to tell the user. Falling back to an in-memory store keeps the
        // app usable for this session; the banner keeps it honest about the fact that nothing
        // written now will still be there tomorrow. Silently swapping in an empty store would
        // let a student believe their work had been deleted.
        let (container, isEphemeral) = Self.makeContainer()
        self.repository = SwiftDataTaskRepository(modelContainer: container)
        self.storeIsEphemeral = isEphemeral
    }

    var body: some Scene {
        WindowGroup {
            TodayView(
                model: TodayViewModel(repository: repository),
                storeIsEphemeral: storeIsEphemeral,
                // Capture is built on demand so each visit starts from a clean sheet rather
                // than from whatever the last one was abandoned mid-way through.
                makeCaptureModel: { CaptureViewModel(repository: repository) }
            )
        }
    }

    /// Set by the UI test target so each run starts from a clean store.
    ///
    /// Without this the UI tests would share the simulator's real database: the golden-path
    /// test completes a task, that completion persists, and after enough runs there is nothing
    /// left to recommend and the suite starts failing for reasons that have nothing to do with
    /// the code. A test that depends on how many times it has been run before is not a test.
    static let uiTestingArgument = "-ui-testing"

    private static func makeContainer() -> (ModelContainer, Bool) {
        if ProcessInfo.processInfo.arguments.contains(uiTestingArgument) {
            do {
                return (
                    try ModelContainer(
                        for: StoredTask.self,
                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                    ),
                    // Not a warning here: ephemeral is exactly what was asked for, so showing
                    // the banner would put a message on screen in every UI test snapshot.
                    false
                )
            } catch {
                fatalError("NEXT could not create an in-memory store for UI testing: \(error)")
            }
        }

        do {
            return (
                try ModelContainer(
                    for: StoredTask.self,
                    migrationPlan: NextMigrationPlan.self
                ),
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
