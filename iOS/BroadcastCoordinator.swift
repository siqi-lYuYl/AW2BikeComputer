import Foundation
import Observation
import UIKit

/// Wires the Watch link to the BLE peripheral: every sample that arrives from the
/// Watch is pushed straight into the heart rate characteristic.
@Observable
final class BroadcastCoordinator {

    let broadcaster = HeartRateBroadcaster()
    let connectivity = PhoneConnectivity()

    private(set) var isBroadcasting = false

    init() {
        connectivity.onSample = { [weak self] sample in
            guard let self, self.isBroadcasting else { return }
            guard sample.streaming else { return }
            self.broadcaster.update(bpm: sample.bpm, sampledAt: sample.date)
        }
        connectivity.activate()
    }

    func startBroadcasting() {
        isBroadcasting = true
        broadcaster.start()
        // Pairing requires the app to stay in the foreground, so keep the screen on.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stopBroadcasting() {
        isBroadcasting = false
        broadcaster.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
