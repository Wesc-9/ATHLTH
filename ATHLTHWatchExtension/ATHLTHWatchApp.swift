import SwiftUI

@main
struct ATHLTHWatchApp: App {
    @StateObject private var routeStore = WatchRouteStore()

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(routeStore)
        }
    }
}
