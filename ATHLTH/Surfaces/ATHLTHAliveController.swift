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
    private static var resetExpressionTask: Task<Void, Never>?
    private static var expression: ATHLTHAliveExpression = .awake
    private static var lastNavigationReaction = Date.distantPast

    static func reconcile(isForeground: Bool) {
        let wasAllowed = foregroundAllowed
        foregroundAllowed = isForeground
        if !isForeground {
            resetExpressionTask?.cancel()
            resetExpressionTask = nil
            expression = .awake
        } else if !wasAllowed && !workoutActive {
            react(.hello)
        }
        scheduleReconciliation()
    }

    static func workoutDidChange(isActive: Bool) {
        let wasActive = workoutActive
        workoutActive = isActive
        if isActive {
            resetExpressionTask?.cancel()
            resetExpressionTask = nil
            expression = .awake
        } else if wasActive && foregroundAllowed {
            react(.excited)
        }
        scheduleReconciliation()
    }

    static func navigationDidChange() {
        guard foregroundAllowed, !workoutActive,
              Date().timeIntervalSince(lastNavigationReaction) >= 8,
              expression == .awake else { return }
        lastNavigationReaction = Date()
        react(.wink)
    }

    private static func react(_ next: ATHLTHAliveExpression) {
        guard foregroundAllowed, !workoutActive else { return }
        resetExpressionTask?.cancel()
        expression = next
        scheduleReconciliation()
        resetExpressionTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            guard !Task.isCancelled, foregroundAllowed, !workoutActive else { return }
            expression = .awake
            scheduleReconciliation()
            resetExpressionTask = nil
        }
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
                if activity.content.state.expression != expression.rawValue {
                    await activity.update(ActivityContent(
                        state: .init(expression: expression.rawValue),
                        staleDate: nil
                    ))
                }
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
                state: ATHLTHAliveActivityAttributes.ContentState(expression: expression.rawValue),
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
