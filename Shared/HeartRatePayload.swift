import Foundation

/// Wire format for messages passed between the Watch and iPhone apps over
/// WatchConnectivity. Dictionary-based because `WCSession` only accepts
/// property-list types.
enum HeartRatePayload {

    private enum Key {
        static let bpm = "bpm"
        static let timestamp = "ts"
        static let streaming = "streaming"
        static let command = "cmd"
    }

    struct Sample {
        let bpm: Int
        let date: Date
        /// False when the Watch has stopped its workout session and is signing off.
        let streaming: Bool
    }

    // MARK: Watch → iPhone

    static func encode(bpm: Int, date: Date = Date(), streaming: Bool = true) -> [String: Any] {
        [
            Key.bpm: bpm,
            Key.timestamp: date.timeIntervalSince1970,
            Key.streaming: streaming,
        ]
    }

    static func decode(_ dictionary: [String: Any]) -> Sample? {
        guard let bpm = dictionary[Key.bpm] as? Int else { return nil }
        let timestamp = dictionary[Key.timestamp] as? TimeInterval
        let streaming = dictionary[Key.streaming] as? Bool ?? true
        return Sample(
            bpm: bpm,
            date: timestamp.map(Date.init(timeIntervalSince1970:)) ?? Date(),
            streaming: streaming
        )
    }

    // MARK: iPhone → Watch

    static let stopCommand: [String: Any] = [Key.command: "stop"]

    static func isStopCommand(_ dictionary: [String: Any]) -> Bool {
        dictionary[Key.command] as? String == "stop"
    }
}
