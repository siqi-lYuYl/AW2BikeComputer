import Foundation
import HealthKit
import Observation
import UIKit

/// Single control surface for the whole system. Tapping start on the phone
/// launches the Watch app remotely and begins advertising; tapping stop tears
/// both down. The user never has to touch the Watch.
@Observable
final class BroadcastCoordinator {

    let broadcaster = HeartRateBroadcaster()
    let connectivity = PhoneConnectivity()

    private(set) var isBroadcasting = false

    private let healthStore = HKHealthStore()

    init() {
        connectivity.onSample = { [weak self] sample in
            guard let self, self.isBroadcasting else { return }
            guard sample.streaming else { return }
            self.broadcaster.update(bpm: sample.bpm, sampledAt: sample.date)
        }
        connectivity.activate()
    }

    func toggle() {
        if isBroadcasting {
            stopBroadcasting()
        } else {
            startBroadcasting()
        }
    }

    func startBroadcasting() {
        isBroadcasting = true
        broadcaster.start()
        launchWatchApp()
        // Pairing requires the app to stay in the foreground, so keep the screen on.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stopBroadcasting() {
        isBroadcasting = false
        broadcaster.stop()
        connectivity.sendStop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func launchWatchApp() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .outdoor
        // Hands the configuration to the Watch app's WKApplicationDelegate,
        // which starts the workout session without any interaction on the Watch.
        healthStore.startWatchApp(with: configuration) { _, _ in }
    }
}
