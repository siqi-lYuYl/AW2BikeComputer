import Foundation
import HealthKit
import Observation

/// Drives a HealthKit workout session purely to keep heart rate flowing. Outside a
/// workout, watchOS samples the heart only every few minutes and suspends the app;
/// inside one it delivers readings every few seconds and keeps us running.
@Observable
final class WorkoutHeartRateMonitor: NSObject {

    enum AuthorizationState {
        case unknown
        case granted
        case denied(String)
    }

    private(set) var currentBPM: Int?
    private(set) var isRunning = false
    private(set) var authorization: AuthorizationState = .unknown
    private(set) var errorMessage: String?

    /// Called on the main queue for each new reading.
    var onSample: ((Int, Date) -> Void)?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private let heartRateType = HKQuantityType(.heartRate)
    private let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorization = .denied("Health data isn't available on this device.")
            return
        }

        let share: Set<HKSampleType> = [HKQuantityType.workoutType()]
        let read: Set<HKObjectType> = [heartRateType, HKQuantityType.workoutType()]

        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            authorization = .granted
        } catch {
            authorization = .denied(error.localizedDescription)
        }
    }

    // MARK: - Session control

    func start() {
        guard !isRunning, HKHealthStore.isHealthDataAvailable() else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { [weak self] _, error in
                guard let error else { return }
                DispatchQueue.main.async { self?.errorMessage = error.localizedDescription }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// - Parameter saveWorkout: when false the session is discarded so no cycling
    ///   workout is written to Health — useful when the bike computer is the
    ///   system of record for the ride.
    func stop(saveWorkout: Bool) {
        guard let session, let builder else { return }

        session.end()
        builder.endCollection(withEnd: Date()) { _, _ in
            if saveWorkout {
                builder.finishWorkout { _, _ in }
            } else {
                builder.discardWorkout()
            }
        }

        self.session = nil
        self.builder = nil
        isRunning = false
        currentBPM = nil
    }
}

extension WorkoutHeartRateMonitor: HKWorkoutSessionDelegate {

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        DispatchQueue.main.async { self.isRunning = (toState == .running) }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            self.isRunning = false
        }
    }
}

extension WorkoutHeartRateMonitor: HKLiveWorkoutBuilderDelegate {

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard collectedTypes.contains(heartRateType),
              let statistics = workoutBuilder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity()
        else { return }

        let bpm = Int(quantity.doubleValue(for: bpmUnit).rounded())
        let sampleDate = statistics.mostRecentQuantityDateInterval()?.end ?? Date()

        DispatchQueue.main.async {
            self.currentBPM = bpm
            self.onSample?(bpm, sampleDate)
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
