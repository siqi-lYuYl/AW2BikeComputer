import CoreBluetooth
import Foundation
import Observation

/// Presents the iPhone to bike computers as a standard Bluetooth LE heart rate
/// sensor: GATT service 0x180D with a notifying Heart Rate Measurement
/// characteristic (0x2A37). Any head unit that pairs with a chest strap — Garmin
/// Edge, Wahoo ELEMNT, Hammerhead — will find it with no special support.
@Observable
final class HeartRateBroadcaster: NSObject {

    enum Status: Equatable {
        case idle
        case bluetoothOff
        case unauthorized
        case unsupported
        case advertising
        case connected(centrals: Int)

        var isLive: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    private enum GATT {
        static let heartRateService = CBUUID(string: "180D")
        static let heartRateMeasurement = CBUUID(string: "2A37")
        static let bodySensorLocation = CBUUID(string: "2A38")
        static let deviceInformationService = CBUUID(string: "180A")
        static let manufacturerName = CBUUID(string: "2A29")
        static let modelNumber = CBUUID(string: "2A24")

        /// Body Sensor Location enum value for "Wrist".
        static let wrist: UInt8 = 0x02
    }

    /// A sample older than this is still broadcast, but with the sensor-contact
    /// bit cleared so the head unit can show the reading as unreliable.
    private static let stalenessThreshold: TimeInterval = 10

    private static let restoreIdentifier = "com.heartrateecho.peripheral"

    private(set) var status: Status = .idle
    private(set) var currentBPM: Int?
    private(set) var subscriberCount = 0
    private(set) var notificationsSent = 0
    private(set) var lastSampleDate: Date?

    /// Name shown in the bike computer's sensor list while the app is in the foreground.
    let advertisedName = "HR Echo"

    private var peripheralManager: CBPeripheralManager?
    private var measurementCharacteristic: CBMutableCharacteristic?
    private var keepAliveTimer: Timer?
    private var wantsToAdvertise = false
    private var didAddServices = false

    var isSampleFresh: Bool {
        guard let lastSampleDate else { return false }
        return Date().timeIntervalSince(lastSampleDate) < Self.stalenessThreshold
    }

    // MARK: - Lifecycle

    func start() {
        wantsToAdvertise = true

        if peripheralManager == nil {
            // Passing a nil queue delivers every delegate callback on the main
            // queue, which is what the observable properties below expect.
            peripheralManager = CBPeripheralManager(
                delegate: self,
                queue: nil,
                options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
            )
        } else {
            beginAdvertisingIfReady()
            refreshStatus()
        }

        startKeepAliveTimer()
    }

    func stop() {
        wantsToAdvertise = false
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        peripheralManager?.stopAdvertising()
        // Dropping the services disconnects paired head units, so they stop
        // showing a sensor that is no longer sending anything.
        peripheralManager?.removeAllServices()
        didAddServices = false
        measurementCharacteristic = nil
        subscriberCount = 0
        currentBPM = nil
        lastSampleDate = nil
        status = .idle
    }

    /// Feed a new reading in from the Watch. Notifications also repeat on a timer,
    /// so head units keep seeing traffic between HealthKit samples.
    func update(bpm: Int, sampledAt date: Date = Date()) {
        currentBPM = bpm
        lastSampleDate = date
        notifySubscribers()
    }

    // MARK: - GATT setup

    private func buildServices() -> [CBMutableService] {
        let measurement = CBMutableCharacteristic(
            type: GATT.heartRateMeasurement,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )
        measurementCharacteristic = measurement

        let location = CBMutableCharacteristic(
            type: GATT.bodySensorLocation,
            properties: [.read],
            value: Data([GATT.wrist]),
            permissions: [.readable]
        )

        let heartRate = CBMutableService(type: GATT.heartRateService, primary: true)
        heartRate.characteristics = [measurement, location]

        // Some head units query Device Information before trusting a sensor.
        let deviceInfo = CBMutableService(type: GATT.deviceInformationService, primary: true)
        deviceInfo.characteristics = [
            CBMutableCharacteristic(
                type: GATT.manufacturerName,
                properties: [.read],
                value: Data("HR Echo".utf8),
                permissions: [.readable]
            ),
            CBMutableCharacteristic(
                type: GATT.modelNumber,
                properties: [.read],
                value: Data("Apple Watch".utf8),
                permissions: [.readable]
            ),
        ]

        return [heartRate, deviceInfo]
    }

    private func beginAdvertisingIfReady() {
        guard let peripheralManager, peripheralManager.state == .poweredOn, wantsToAdvertise else { return }

        if !didAddServices {
            didAddServices = true
            buildServices().forEach(peripheralManager.add)
        }

        guard !peripheralManager.isAdvertising else { return }
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [GATT.heartRateService],
            CBAdvertisementDataLocalNameKey: advertisedName,
        ])
    }

    // MARK: - Notifying

    private func startKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.notifySubscribers()
        }
        // .common keeps the 1 Hz cadence alive while the user scrolls the UI.
        RunLoop.main.add(timer, forMode: .common)
        keepAliveTimer = timer
    }

    private func notifySubscribers() {
        guard let peripheralManager,
              let measurementCharacteristic,
              let currentBPM,
              subscriberCount > 0
        else { return }

        let packet = Self.measurementPacket(bpm: currentBPM, contactDetected: isSampleFresh)
        // Returns false when the transmit queue is full; the retry arrives via
        // peripheralManagerIsReady(toUpdateSubscribers:).
        if peripheralManager.updateValue(packet, for: measurementCharacteristic, onSubscribedCentrals: nil) {
            notificationsSent += 1
        }
    }

    /// Heart Rate Measurement characteristic, Bluetooth SIG layout:
    /// byte 0 = flags, byte 1 = BPM as UInt8 (flags bit 0 clear).
    /// Flags bit 1 = sensor contact detected, bit 2 = sensor contact supported.
    static func measurementPacket(bpm: Int, contactDetected: Bool) -> Data {
        var flags: UInt8 = 0b0000_0100
        if contactDetected { flags |= 0b0000_0010 }
        return Data([flags, UInt8(clamping: bpm)])
    }

    private func refreshStatus() {
        guard wantsToAdvertise else {
            status = .idle
            return
        }
        if subscriberCount > 0 {
            status = .connected(centrals: subscriberCount)
        } else {
            status = .advertising
        }
    }
}

extension HeartRateBroadcaster: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            beginAdvertisingIfReady()
            refreshStatus()
        case .poweredOff:
            status = .bluetoothOff
        case .unauthorized:
            status = .unauthorized
        case .unsupported:
            status = .unsupported
        default:
            status = .idle
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        wantsToAdvertise = true
        didAddServices = true
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
            measurementCharacteristic = services
                .compactMap(\.characteristics)
                .flatMap { $0 }
                .compactMap { $0 as? CBMutableCharacteristic }
                .first { $0.uuid == GATT.heartRateMeasurement }
        }
        startKeepAliveTimer()
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        guard characteristic.uuid == GATT.heartRateMeasurement else { return }
        subscriberCount += 1
        refreshStatus()
        notifySubscribers()
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        guard characteristic.uuid == GATT.heartRateMeasurement else { return }
        subscriberCount = max(0, subscriberCount - 1)
        refreshStatus()
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        notifySubscribers()
    }
}
