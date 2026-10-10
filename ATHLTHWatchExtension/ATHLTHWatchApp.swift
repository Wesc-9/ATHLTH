import HealthKit
import SwiftUI
import WatchKit

@main
struct ATHLTHWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self)
    private var appDelegate

    @StateObject private var routeStore = WatchRouteStore.shared
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
        Task { @MainActor in
            await handleIPhoneWorkoutLaunch(workoutConfiguration)
        }
    }

    @MainActor
    private func handleIPhoneWorkoutLaunch(
        _ configuration: HKWorkoutConfiguration
    ) async {
        let manager = WatchWorkoutManager.shared
        let routeStore = WatchRouteStore.shared

        // Only quick runs with an explicit automatic start mode use the
        // prepared-workout handshake. All other HealthKit launches retain
        // their existing behavior.
        guard configuration.activityType == .running else {
            await manager.start(configuration: configuration)
            return
        }

        let requestedAt = Date()
        let deadline = requestedAt.addingTimeInterval(15)
        while Date() < deadline {
            // A second request must never create a second HKWorkoutSession.
            if manager.isActive ||
                manager.state == .preparing ||
                manager.state == .ending {
                return
            }

            if let workout = routeStore.preparedWorkout,
               workout.kind == .running,
               let mode = workout.startMode,
               mode != .onWatch,
               workout.updatedAt >= requestedAt.addingTimeInterval(-20),
               workout.indoor == (configuration.locationType == .indoor) {
                let routeReady = workout.routeID == nil ||
                    workout.routeID.flatMap {
                        routeStore.route(with: $0)
                    } != nil

                if routeReady {
                    if mode == .afterThirtySeconds {
                        let startAt = workout.updatedAt.addingTimeInterval(30)
                        while Date() < startAt {
                            if manager.isActive ||
                                manager.state == .preparing ||
                                manager.state == .ending {
                                routeStore.setAutomaticStartCountdown(nil)
                                return
                            }

                            routeStore.setAutomaticStartCountdown(
                                max(1, Int(ceil(startAt.timeIntervalSinceNow)))
                            )
                            try? await Task.sleep(for: .milliseconds(250))
                        }
                    }

                    routeStore.setAutomaticStartCountdown(nil)
                    await routeStore.launchPreparedWorkout(
                        workout,
                        manager: manager
                    )
                    return
                }
            }

            try? await Task.sleep(for: .milliseconds(200))
        }

        // WatchConnectivity can be delayed while the Watch app wakes up.
        // Do not drop the start request: record a normal HealthKit workout
        // rather than leave the user with a false "sent" confirmation.
        routeStore.setAutomaticStartCountdown(nil)
        await manager.start(configuration: configuration)
    }

    func handleActiveWorkoutRecovery() {
        Task {
            await WatchWorkoutManager.shared
                .recoverActiveWorkout()
        }
    }
}
