import HealthKit
import SwiftUI
import WatchKit

@main
struct HeartRateEchoWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchContentView(session: EchoSession.shared)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {

    /// Entry point when the iPhone calls `HKHealthStore.startWatchApp(with:)`.
    /// watchOS launches us (in the background if needed) and hands over the
    /// configuration; starting the session here means no taps on the Watch.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await EchoSession.shared.start()
        }
    }
}
