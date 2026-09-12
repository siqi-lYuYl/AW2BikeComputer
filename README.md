# HR Echo

Broadcasts your Apple Watch heart rate to a bike computer in real time, the way
apps like Echo do. Your Garmin Edge, Wahoo ELEMNT or Hammerhead sees a normal
Bluetooth heart rate strap and pairs with it — no special support needed.

## How it works

watchOS cannot act as a Bluetooth LE peripheral, so the Watch can't advertise
itself as a heart rate sensor. The iPhone does that job instead:

```
Apple Watch                         iPhone                        Bike computer
───────────                         ──────                        ─────────────
HKWorkoutSession                    CBPeripheralManager
  ↓ live heart rate                   ↓ GATT 0x180D
HKLiveWorkoutBuilder  ──────────→  advertises as a  ──────────→  pairs as a
                     WatchConnectivity  HR sensor       BLE notify   HR strap
```

- **Watch** — a HealthKit cycling workout session keeps the app alive and raises
  heart rate sampling from once every few minutes to every few seconds.
- **Link** — `WCSession.sendMessage` for low latency; it also wakes the iPhone
  app in the background if it isn't running. Application context is the
  latest-value-wins fallback when the phone is briefly unreachable.
- **iPhone** — publishes the standard Heart Rate Service (`0x180D`) with a
  notifying Heart Rate Measurement characteristic (`0x2A37`), plus Body Sensor
  Location and Device Information. Notifications repeat at 1 Hz so head units
  keep seeing traffic between HealthKit samples; readings older than 10 seconds
  are still sent but with the sensor-contact bit cleared.

## Building

The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate && open HeartRateEcho.xcodeproj
```

Set your development team on both targets, then run the **HeartRateEcho** scheme
on your iPhone — the Watch app is embedded and installs alongside it.

Bundle identifiers derive from the `APP_BUNDLE_ID` build setting in
`project.yml`; change it there and both targets follow.

## Testing

This cannot be tested in the Simulator: there is no Bluetooth radio and no heart
rate sensor. You need a real iPhone, a real Apple Watch and a head unit.

1. Open the app on the iPhone and tap **Start Broadcasting**.
2. On the Watch, tap **Start** and grant Health access.
3. On the bike computer, add a new heart rate sensor and select **HR Echo**.

## Known limitations

- **Pair with the iPhone app in the foreground.** When an iOS app advertises
  from the background, the local name is dropped and service UUIDs move to an
  "overflow" area that only other Apple devices can scan. A bike computer will
  not discover it. Once paired the connection survives backgrounding, but
  leaving the app on screen is the reliable path.
- HealthKit requires a paid Apple Developer Program membership; the free
  personal team cannot sign the HealthKit entitlement.
- The Watch writes a cycling workout to Health on stop so the ride still counts
  toward Activity rings. Turn off **Save workout** on the Watch if your bike
  computer already syncs the same ride.
