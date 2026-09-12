import SwiftUI

struct WatchContentView: View {
    @Bindable var session: EchoSession

    private var monitor: WorkoutHeartRateMonitor { session.monitor }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                readout

                if let errorMessage = monitor.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                actionButton

                if !monitor.isRunning {
                    Toggle("Save workout", isOn: $session.savesWorkoutToHealth)
                        .font(.caption)
                }

                phoneStatus
            }
            .padding(.horizontal, 4)
        }
    }

    private var readout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .symbolEffect(.pulse, isActive: monitor.isRunning)
                Text(monitor.currentBPM.map(String.init) ?? "—")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: monitor.currentBPM)
            }
            Text("BPM")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var actionButton: some View {
        Button {
            if monitor.isRunning {
                session.stop()
            } else {
                Task { await session.start() }
            }
        } label: {
            Text(monitor.isRunning ? "Stop" : "Start")
                .frame(maxWidth: .infinity)
        }
        .tint(monitor.isRunning ? .red : .pink)
    }

    private var phoneStatus: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(session.connectivity.isPhoneReachable ? .green : .orange)
                .frame(width: 6, height: 6)
            Text(session.connectivity.isPhoneReachable ? "iPhone linked" : "iPhone unreachable")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    WatchContentView(session: EchoSession())
}
