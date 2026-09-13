import Foundation
import Observation
import WatchConnectivity

/// Watch end of the link. `sendMessage` is the low-latency path and will launch
/// the iPhone app in the background if it isn't running; application context is
/// the latest-value-wins fallback for when the phone is briefly unreachable.
@Observable
final class WatchConnectivityClient: NSObject {

    private(set) var isPhoneReachable = false

    /// Called on the main queue when the iPhone asks us to end the session.
    var onStopCommand: (() -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(bpm: Int, sampledAt date: Date, streaming: Bool = true) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let payload = HeartRatePayload.encode(bpm: bpm, date: date, streaming: streaming)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                self?.queueAsContext(payload)
            }
        } else {
            queueAsContext(payload)
        }
    }

    private func queueAsContext(_ payload: [String: Any]) {
        try? WCSession.default.updateApplicationContext(payload)
    }

    private func handleCommand(_ dictionary: [String: Any]) {
        guard HeartRatePayload.isStopCommand(dictionary) else { return }
        DispatchQueue.main.async { self.onStopCommand?() }
    }
}

extension WatchConnectivityClient: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { self.isPhoneReachable = session.isReachable }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isPhoneReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleCommand(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleCommand(userInfo)
    }
}
