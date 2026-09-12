import SwiftUI

@main
struct HeartRateEchoWatchApp: App {
    @State private var session = EchoSession()

    var body: some Scene {
        WindowGroup {
            WatchContentView(session: session)
        }
    }
}
