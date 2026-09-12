import Foundation
import Observation

/// Ties the workout heart rate stream to the phone link.
@Observable
final class EchoSession {

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
        if let bpm = monitor.currentBPM {
            connectivity.send(bpm: bpm, sampledAt: Date(), streaming: false)
        }
        monitor.stop(saveWorkout: savesWorkoutToHealth)
    }
}
