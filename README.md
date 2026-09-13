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

## Using it

The iPhone is the only control surface. Tap the heart:

- it turns **red** — the phone starts advertising and remotely launches the
  Watch app, which begins the workout session (first run asks for Health access
  on the Watch);
- it starts **pounding** — live readings are arriving from the Watch, and the
  beat follows your actual heart rate;
- **glows** flow outward — a bike computer has paired and is receiving data.

Tap again to stop both ends.

## Testing

The Bluetooth half cannot be tested in the Simulator: there is no radio, so the
iPhone reports "Bluetooth isn't available." Everything else can. The watchOS
Simulator synthesises heart rate during a workout session and WatchConnectivity
works between a paired iPhone and Watch simulator. When installing with
`simctl`, install the Watch app first (the embedded copy under
`HeartRateEcho.app/Watch/`) and launch it before the phone app, or the phone
reports the counterpart as not installed.

A real head unit needs a real iPhone and Watch. Add a new heart rate sensor on
the bike computer and select **HR Echo**.

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
