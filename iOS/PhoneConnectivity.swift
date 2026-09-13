import Foundation
import Observation
import WatchConnectivity

/// iPhone end of the Watch link. `sendMessage` from the Watch wakes this app in
/// the background, so the phone does not need to be on screen to keep relaying.
@Observable
final class PhoneConnectivity: NSObject {

    private(set) var isWatchReachable = false
    private(set) var lastReceivedAt: Date?

    /// Set by the coordinator; called on the main queue.
    var onSample: ((HeartRatePayload.Sample) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendStop() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let payload = HeartRatePayload.stopCommand
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            // Queued and guaranteed, so the Watch stops even if it's asleep right now.
            session.transferUserInfo(payload)
        }
    }

    private func handle(_ dictionary: [String: Any]) {
        guard let sample = HeartRatePayload.decode(dictionary) else { return }
        DispatchQueue.main.async {
            self.lastReceivedAt = Date()
            self.onSample?(sample)
        }
    }
}

extension PhoneConnectivity: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { self.isWatchReachable = session.isReachable }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isWatchReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
