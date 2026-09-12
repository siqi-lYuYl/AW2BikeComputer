import SwiftUI

struct ContentView: View {
    let coordinator: BroadcastCoordinator

    private var broadcaster: HeartRateBroadcaster { coordinator.broadcaster }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                heartRateReadout

                statusPanel

                Spacer()

                if coordinator.isBroadcasting {
                    pairingHint
                }

                actionButton
            }
            .padding()
            .navigationTitle("HR Echo")
        }
    }

    private var heartRateReadout: some View {
        VStack(spacing: 4) {
            Text(broadcaster.currentBPM.map(String.init) ?? "—")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(broadcaster.isSampleFresh ? .pink : .secondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: broadcaster.currentBPM)

            Text("BPM")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }

    private var statusPanel: some View {
        VStack(spacing: 12) {
            statusRow(
                label: "Apple Watch",
                value: coordinator.connectivity.isWatchReachable ? "Connected" : "Not reachable",
                isGood: coordinator.connectivity.isWatchReachable
            )
            Divider()
            statusRow(
                label: "Bike computer",
                value: bluetoothStatusText,
                isGood: broadcaster.status.isLive
            )
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }

    private func statusRow(label: String, value: String, isGood: Bool) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Circle()
                .fill(isGood ? .green : .orange)
                .frame(width: 8, height: 8)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private var bluetoothStatusText: String {
        switch broadcaster.status {
        case .idle: "Not broadcasting"
        case .bluetoothOff: "Bluetooth is off"
        case .unauthorized: "Bluetooth permission denied"
        case .unsupported: "Not supported"
        case .advertising: "Waiting to pair"
        case .connected(let centrals): centrals == 1 ? "Paired" : "Paired (\(centrals))"
        }
    }

    private var pairingHint: some View {
        Text(broadcaster.status.isLive
             ? "Streaming. Keep this app open for the most reliable connection."
             : "On your bike computer, add a new heart rate sensor and pick “\(broadcaster.advertisedName)”. Keep this screen open while pairing.")
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
    }

    private var actionButton: some View {
        Button {
            if coordinator.isBroadcasting {
                coordinator.stopBroadcasting()
            } else {
                coordinator.startBroadcasting()
            }
        } label: {
            Text(coordinator.isBroadcasting ? "Stop Broadcasting" : "Start Broadcasting")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(coordinator.isBroadcasting ? .red : .pink)
    }
}

#Preview {
    ContentView(coordinator: BroadcastCoordinator())
}
