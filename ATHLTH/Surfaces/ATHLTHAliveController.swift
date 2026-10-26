import ActivityKit
import Foundation
import UIKit

/// Isolated proof of concept. Never interrupts an active workout.
@MainActor
enum ATHLTHAliveController {
    private static var revision: UInt64 = 0

    static func reconcile(isForeground: Bool) {
        revision &+= 1
        let currentRevision = revision
        Task {
            if !isForeground {
                await stop()
                return
            }
            guard ActivityAuthorizationInfo().areActivitiesEnabled,
                  UIApplication.shared.applicationState == .active,
                  Activity<ATHLTHWorkoutActivityAttributes>.activities.isEmpty
            else {
                await stop()
                return
            }
            guard currentRevision == revision else { return }
            if Activity<ATHLTHAliveActivityAttributes>.activities.isEmpty {
                do {
                    let attributes = ATHLTHAliveActivityAttributes(openedAt: Date())
                    let content = ActivityContent(
                        state: ATHLTHAliveActivityAttributes.ContentState(expression: "awake"),
                        staleDate: nil
                    )
                    _ = try Activity.request(
                        attributes: attributes,
                        content: content,
                        pushType: nil
                    )
                } catch {
                    // Experimental UI never blocks ordinary app use.
                }
            }
        }
    }

    static func stop() async {
        for activity in Activity<ATHLTHAliveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func workoutDidChange(isActive: Bool) {
        if isActive {
            revision &+= 1
            Task { await stop() }
        } else {
            reconcile(isForeground: UIApplication.shared.applicationState == .active)
        }
    }
}
