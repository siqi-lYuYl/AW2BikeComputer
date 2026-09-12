import SwiftUI

@main
struct HeartRateEchoApp: App {
    @State private var coordinator = BroadcastCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView(coordinator: coordinator)
        }
    }
}
