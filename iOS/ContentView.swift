import SwiftUI

struct ContentView: View {
    let coordinator: BroadcastCoordinator

    private var broadcaster: HeartRateBroadcaster { coordinator.broadcaster }

    /// The line only trembles while live readings are arriving from the Watch.
    private var pulseBPM: Int? {
        guard coordinator.isBroadcasting, broadcaster.isSampleFresh else { return nil }
        return broadcaster.currentBPM
    }

    private var lineColor: Color {
        coordinator.isBroadcasting ? .red : .primary
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)

            TremblingLine(bpm: pulseBPM, color: lineColor)

            ZStack {
                if broadcaster.status.isLive {
                    GlowRipples(color: .red)
                        .transition(.opacity)
                }

                if coordinator.isBroadcasting, let bpm = broadcaster.currentBPM {
                    Text("\(bpm)")
                        .font(.system(size: 56, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.red)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: bpm)
                        .offset(y: 8)
                }

                Color.clear
                    .frame(width: HeartGeometry.tapSize, height: HeartGeometry.tapSize)
                    .contentShape(.rect)
                    .onTapGesture(perform: coordinator.toggle)
            }
            .offset(y: HeartGeometry.centerOffsetY)
            .animation(.easeInOut(duration: 0.6), value: broadcaster.status.isLive)

            VStack {
                Spacer()
                if let caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 48)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: caption)
        }
        .ignoresSafeArea()
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

// MARK: - Geometry

/// All coordinates for the one-line drawing live here so the trembling line,
/// the glow ripples and the tap target agree on where the heart is.
private enum HeartGeometry {
    static let lineWidth: CGFloat = 2.2
    static let centerOffsetY: CGFloat = -24
    static let tapSize: CGFloat = 240
    static let loopSize = CGSize(width: 236, height: 212)

    struct Segment {
        let c1: CGPoint
        let c2: CGPoint
        let to: CGPoint
        /// Tails stay calm; only the heart itself shudders.
        let trembles: Bool
    }

    static func center(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY + centerOffsetY)
    }

    /// Right extreme → right lobe → dip → left lobe → left extreme.
    private static func lobes(_ c: CGPoint) -> [Segment] {
        [
            Segment(c1: c + (105, -62), c2: c + (86, -96), to: c + (56, -96), trembles: true),
            Segment(c1: c + (26, -96), c2: c + (8, -66), to: c + (0, -46), trembles: true),
            Segment(c1: c + (-8, -66), c2: c + (-26, -96), to: c + (-56, -96), trembles: true),
            Segment(c1: c + (-86, -96), c2: c + (-105, -62), to: c + (-105, -8), trembles: true),
        ]
    }

    /// The closed heart on its own, used for the ripples.
    static func loop(center c: CGPoint) -> (start: CGPoint, segments: [Segment]) {
        let bottom = c + (0, 92)
        var segments = [Segment(c1: c + (48, 62), c2: c + (105, 40), to: c + (105, -8), trembles: true)]
        segments += lobes(c)
        segments.append(Segment(c1: c + (-105, 40), c2: c + (-48, 62), to: bottom, trembles: true))
        return (bottom, segments)
    }

    /// The full drawing: a tail sweeping in from the top-left, the heart, and a
    /// tail running off the bottom. The two sides of the heart cross just below
    /// its point, the way a pen would.
    static func line(in rect: CGRect) -> (start: CGPoint, segments: [Segment]) {
        let c = center(in: rect)
        let w = rect.width
        let h = rect.height

        let start = CGPoint(x: rect.minX - 12, y: rect.minY + 0.07 * h)
        var segments: [Segment] = [
            // Bow in from the left edge, then descend well clear of the heart.
            Segment(
                c1: CGPoint(x: rect.minX + 0.22 * w, y: rect.minY + 0.09 * h),
                c2: CGPoint(x: rect.minX + 0.15 * w, y: rect.minY + 0.24 * h),
                to: CGPoint(x: rect.minX + 0.15 * w, y: c.y - 30),
                trembles: false
            ),
            // Sweep under the heart's point and into its right side.
            Segment(
                c1: CGPoint(x: rect.minX + 0.15 * w, y: c.y + 85),
                c2: c + (-80, 102),
                to: c + (-10, 92),
                trembles: false
            ),
            Segment(c1: c + (45, 80), c2: c + (105, 45), to: c + (105, -8), trembles: true),
        ]
        segments += lobes(c)
        segments += [
            // Down the left side, crossing the entry line just below the point.
            Segment(c1: c + (-105, 40), c2: c + (-55, 75), to: c + (-15, 105), trembles: true),
            Segment(
                c1: c + (40, 145),
                c2: CGPoint(x: rect.minX + 0.60 * w, y: rect.maxY - 0.18 * h),
                to: CGPoint(x: rect.minX + 0.42 * w, y: rect.maxY + 12),
                trembles: false
            ),
        ]
        return (start, segments)
    }

    /// Flattens the curves into a polyline, nudging each point by a little
    /// layered noise so the stroke looks hand-drawn and shaky rather than
    /// mechanically offset.
    static func polyline(start: CGPoint, segments: [Segment], tremble: Double, time: Double) -> Path {
        let stepsPerSegment = 40
        var points: [CGPoint] = []
        points.reserveCapacity(segments.count * stepsPerSegment + 1)

        var from = start
        for (index, segment) in segments.enumerated() {
            for step in (index == 0 ? 0 : 1)...stepsPerSegment {
                let u = CGFloat(step) / CGFloat(stepsPerSegment)
                var point = cubic(from, segment.c1, segment.c2, segment.to, u)
                if segment.trembles, tremble > 0 {
                    let s = (Double(index) + Double(u)) / Double(segments.count)
                    point = point + jitter(s: s, time: time, amplitude: tremble * 3.5)
                }
                points.append(point)
            }
            from = segment.to
        }

        var path = Path()
        path.addLines(points)
        return path
    }

    private static func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }

    private static func jitter(s: Double, time t: Double, amplitude: Double) -> (CGFloat, CGFloat) {
        let x = 0.55 * sin(s * 131 + t * 43) + 0.30 * sin(s * 71 - t * 31) + 0.15 * sin(s * 293 + t * 89)
        let y = 0.55 * cos(s * 113 - t * 37) + 0.30 * sin(s * 59 + t * 27) + 0.15 * cos(s * 277 - t * 79)
        return (CGFloat(amplitude * x), CGFloat(amplitude * y))
    }
}

private func + (point: CGPoint, offset: (CGFloat, CGFloat)) -> CGPoint {
    CGPoint(x: point.x + offset.0, y: point.y + offset.1)
}

// MARK: - Shapes

struct HeartLineShape: Shape {
    var tremble: Double
    var time: Double

    func path(in rect: CGRect) -> Path {
        let (start, segments) = HeartGeometry.line(in: rect)
        return HeartGeometry.polyline(start: start, segments: segments, tremble: tremble, time: time)
    }
}

struct HeartLoopShape: Shape {
    func path(in rect: CGRect) -> Path {
        let (start, segments) = HeartGeometry.loop(center: CGPoint(x: rect.midX, y: rect.midY))
        return HeartGeometry.polyline(start: start, segments: segments, tremble: 0, time: 0)
    }
}

// MARK: - Views

/// The one-line drawing. While a heart rate is flowing the stroke shudders in
/// a lub-dub rhythm, one cycle per beat, so 60 BPM really is one pulse a second.
struct TremblingLine: View {
    let bpm: Int?
    let color: Color

    var body: some View {
        TimelineView(.animation(paused: bpm == nil)) { context in
            HeartLineShape(tremble: tremble(at: context.date), time: context.date.timeIntervalSinceReferenceDate)
                .stroke(color, style: StrokeStyle(lineWidth: HeartGeometry.lineWidth, lineCap: .round, lineJoin: .round))
        }
        .animation(.easeOut(duration: 0.45), value: color)
        .allowsHitTesting(false)
    }

    private func tremble(at date: Date) -> Double {
        guard let bpm, bpm > 0 else { return 0 }
        let period = 60.0 / Double(bpm)
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
        return Self.lubDub(phase)
    }

    /// Two bumps per beat: a strong first sound, then a softer second one.
    private static func lubDub(_ phase: Double) -> Double {
        max(bump(phase, centre: 0.08, width: 0.10), 0.5 * bump(phase, centre: 0.32, width: 0.09))
    }

    private static func bump(_ x: Double, centre: Double, width: Double) -> Double {
        let d = (x - centre) / width
        return exp(-d * d)
    }
}

/// Echoes of the heart outline that expand outward and fade, staggered so one
/// is always mid-flight. Shown only while a bike computer is subscribed.
struct GlowRipples: View {
    let color: Color

    private let period: TimeInterval = 2.6
    private let count = 3

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    let phase = (now / period + Double(index) / Double(count))
                        .truncatingRemainder(dividingBy: 1)
                    HeartLoopShape()
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                        .frame(width: HeartGeometry.loopSize.width, height: HeartGeometry.loopSize.height)
                        .scaleEffect(1 + phase * 1.7)
                        .opacity((1 - phase) * 0.4)
                        .blur(radius: 1 + phase * 6)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview("Idle") {
    ContentView(coordinator: BroadcastCoordinator())
}
