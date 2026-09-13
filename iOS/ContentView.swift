import SwiftUI

struct ContentView: View {
    let coordinator: BroadcastCoordinator

    private var broadcaster: HeartRateBroadcaster { coordinator.broadcaster }

    /// The heart only pounds while live readings are arriving from the Watch.
    private var pulseBPM: Int? {
        guard coordinator.isBroadcasting, broadcaster.isSampleFresh else { return nil }
        return broadcaster.currentBPM
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            ZStack {
                if broadcaster.status.isLive {
                    GlowRipples(color: .red)
                        .transition(.opacity)
                }

                BeatingHeart(
                    bpm: pulseBPM,
                    color: coordinator.isBroadcasting ? .red : Color(.systemGray4)
                ) {
                    if coordinator.isBroadcasting, let bpm = broadcaster.currentBPM {
                        Text("\(bpm)")
                            .font(.system(size: 60, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: bpm)
                    }
                }
                .contentShape(.rect)
                .onTapGesture(perform: coordinator.toggle)
            }
            .animation(.easeInOut(duration: 0.6), value: broadcaster.status.isLive)

            VStack {
                Spacer()
                if let caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 32)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: caption)
        }
    }

    private var caption: String? {
        switch broadcaster.status {
        case .idle, .connected: nil
        case .advertising: "Pair “\(broadcaster.advertisedName)” on your bike computer"
        case .bluetoothOff: "Turn on Bluetooth"
        case .unauthorized: "Allow Bluetooth for HR Echo in Settings"
        case .unsupported: "Bluetooth isn't available on this device"
        }
    }
}

// MARK: - Heart

private let heartSize: CGFloat = 200

/// A heart that pounds at a given rate. The scale follows a lub-dub curve,
/// one full cycle per beat, so 60 BPM really is one pound per second.
struct BeatingHeart<Label: View>: View {
    let bpm: Int?
    let color: Color
    @ViewBuilder let label: () -> Label

    var body: some View {
        TimelineView(.animation(paused: bpm == nil)) { context in
            heart.scaleEffect(scale(at: context.date))
        }
        .animation(.easeOut(duration: 0.4), value: color)
    }

    private var heart: some View {
        ZStack {
            Image(systemName: "heart.fill")
                .font(.system(size: heartSize))
                .foregroundStyle(color)
            // A heart's visual centre sits a little above its bounding box centre.
            label().offset(y: -heartSize * 0.04)
        }
        .frame(width: heartSize, height: heartSize)
    }

    private func scale(at date: Date) -> CGFloat {
        guard let bpm, bpm > 0 else { return 1 }
        let period = 60.0 / Double(bpm)
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
        return 1 + 0.10 * Self.lubDub(phase)
    }

    /// Two Gaussian bumps: a strong first sound and a softer second one.
    private static func lubDub(_ phase: Double) -> Double {
        max(bump(phase, centre: 0.08, width: 0.07), 0.45 * bump(phase, centre: 0.30, width: 0.07))
    }

    private static func bump(_ x: Double, centre: Double, width: Double) -> Double {
        let d = (x - centre) / width
        return exp(-d * d)
    }
}

// MARK: - Glow

/// Heart-shaped glows that expand outward and fade, staggered so one is always
/// mid-flight. Shown only while a bike computer is subscribed.
struct GlowRipples: View {
    let color: Color

    private let period: TimeInterval = 2.4
    private let count = 3

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    let phase = (now / period + Double(index) / Double(count))
                        .truncatingRemainder(dividingBy: 1)
                    Image(systemName: "heart.fill")
                        .font(.system(size: heartSize))
                        .foregroundStyle(color)
                        .scaleEffect(1 + phase * 1.8)
                        .opacity((1 - phase) * 0.3)
                        .blur(radius: 6 + phase * 14)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview("Idle") {
    ContentView(coordinator: BroadcastCoordinator())
}
