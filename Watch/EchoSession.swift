import Foundation
import Observation

/// Ties the workout heart rate stream to the phone link.
@Observable
final class EchoSession {

    /// Shared because both the SwiftUI scene and the WKApplicationDelegate
    /// (remote launch from the iPhone) need to drive the same session.
    static let shared = EchoSession()

    let monitor = WorkoutHeartRateMonitor()
    let connectivity = WatchConnectivityClient()

    /// When true the cycling workout is written to Health on stop, so the ride
    /// still counts toward Activity rings. Turn off if the bike computer already
    /// syncs the same ride.
    var savesWorkoutToHealth = true

    init() {
        monitor.onSample = { [weak self] bpm, date in
            self?.connectivity.send(bpm: bpm, sampledAt: date)
        }
        connectivity.onStopCommand = { [weak self] in
            self?.stop()
        }
        connectivity.activate()
    }

    func start() async {
        if case .granted = monitor.authorization {} else {
            await monitor.requestAuthorization()
        }
        guard case .granted = monitor.authorization else { return }
        monitor.start()
    }

    func stop() {
        guard monitor.isRunning else { return }
        if let bpm = monitor.currentBPM {
            connectivity.send(bpm: bpm, sampledAt: Date(), streaming: false)
        }
        monitor.stop(saveWorkout: savesWorkoutToHealth)
    }
}
