import HealthKit
import SwiftUI
import WatchKit

@main
struct ATHLTHWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self)
    private var appDelegate

    @StateObject private var routeStore = WatchRouteStore()
    @StateObject private var workoutManager = WatchWorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(routeStore)
                .environmentObject(workoutManager)
                .preferredColorScheme(.light)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task {
            await WatchWorkoutManager.shared.start(
                configuration: workoutConfiguration
            )
        }
    }
}
