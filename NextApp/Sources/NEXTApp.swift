import SwiftUI

/// NEXT — know what to do next.
///
/// The app layer is deliberately thin. Every decision about *what* the user should do lives
/// in `NextKit`, which has no Apple UI dependency and is unit-tested off-device
/// (ARCHITECTURE.md §1). These views render that decision and send intents back.
@main
struct NEXTApp: App {
    var body: some Scene {
        WindowGroup {
            TodayView(model: TodayViewModel(tasks: SampleTasks.starter))
        }
    }
}
