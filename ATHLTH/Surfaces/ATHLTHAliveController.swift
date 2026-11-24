import ActivityKit
import Foundation
import OSLog
import UIKit

/// One serialized owner of the decorative foreground Live Activity.
/// Workout activities always take priority. ActivityKit owns visibility.
@MainActor
enum ATHLTHAliveController {
    private static let logger = Logger(subsystem: "com.wesc9.athlth", category: "Alive")
    private static var foregroundAllowed = false
    private static var workoutActive = false
    private static var revision: UInt64 = 0
    private static var worker: Task<Void, Never>?

    static func reconcile(isForeground: Bool) {
        foregroundAllowed = isForeground
        scheduleReconciliation()
    }

    static func workoutDidChange(isActive: Bool) {
        workoutActive = isActive
        scheduleReconciliation()
    }

    private static func scheduleReconciliation() {
        revision &+= 1
        guard worker == nil else { return }
        worker = Task { @MainActor in
            defer { worker = nil }
            while !Task.isCancelled {
                let requestedRevision = revision
                await applyDesiredState()
                // An ActivityKit end suspends. Re-evaluate the latest intent
                // instead of allowing an old stop to erase a newer activity.
                if requestedRevision == revision { return }
            }
        }
    }

    private static func applyDesiredState() async {
        let permitted = foregroundAllowed && !workoutActive &&
            ActivityAuthorizationInfo().areActivitiesEnabled &&
            Activity<ATHLTHWorkoutActivityAttributes>.activities.isEmpty
        guard permitted else {
            await endAll()
            return
        }

        // Inactive is not background: keep an existing activity during
        // transient system overlays, but request new ones only while active.
        guard UIApplication.shared.applicationState == .active else { return }
        let activities = Activity<ATHLTHAliveActivityAttributes>.activities
        var kept = false
        for activity in activities {
            if !kept && (activity.activityState == .active || activity.activityState == .stale) {
                kept = true
                continue
            }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard foregroundAllowed, !workoutActive,
              UIApplication.shared.applicationState == .active,
              Activity<ATHLTHWorkoutActivityAttributes>.activities.isEmpty,
              Activity<ATHLTHAliveActivityAttributes>.activities.isEmpty
        else { return }

        do {
            let attributes = ATHLTHAliveActivityAttributes(openedAt: Date())
            let content = ActivityContent(
                state: ATHLTHAliveActivityAttributes.ContentState(expression: "awake"),
                staleDate: nil
            )
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            logger.notice("Alive request unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    private static func endAll() async {
        for activity in Activity<ATHLTHAliveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
