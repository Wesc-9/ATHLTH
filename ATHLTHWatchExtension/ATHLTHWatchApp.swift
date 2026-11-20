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

        // Run and walk share the same prepared handoff, so the original
        // plan ID, active steps and route reach the actual Watch recorder.
        // Other simple sports still use their existing HealthKit start.
        let requestedKind: WatchWorkoutKind
        switch configuration.activityType {
        case .running: requestedKind = .running
        case .walking: requestedKind = .walking
        default:
            await manager.start(configuration: configuration)
            return
        }

        let requestedAt = Date()
        // Standalone Watch starts should not wait for a phone transfer
        // they never requested.
        let transferDeadline = requestedAt.addingTimeInterval(2)
        let routeDeadline = requestedAt.addingTimeInterval(15)
        while Date() < routeDeadline {
            // A second request must never create a second HKWorkoutSession.
            if !manager.canAcceptPreparedWorkout() { return }

            if let workout = routeStore.preparedWorkout,
               workout.kind == requestedKind,
               ATHLTHWatchPreparedPlanIdentityPolicy.allows(
                   planID: workout.plannedPlanID,
                   sessionID: workout.plannedSessionID
               ),
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
                            // A newer quick-start request supersedes this
                            // countdown, including switching to manual start.
                            if routeStore.preparedWorkout?.id != workout.id {
                                routeStore.setAutomaticStartCountdown(nil)
                                return
                            }
                            if !manager.canAcceptPreparedWorkout() {
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

            if Date() >= transferDeadline {
                // Once an automatic transfer exists we can wait longer for
                // its route file. Without that transfer, keep legacy Watch
                // launches responsive.
                let waitingForRoute = routeStore.preparedWorkout.map {
                    $0.kind == requestedKind &&
                    $0.startMode != nil &&
                    $0.startMode != .onWatch &&
                    $0.updatedAt >= requestedAt.addingTimeInterval(-20)
                } ?? false
                if !waitingForRoute { break }
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
