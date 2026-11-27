import Foundation

/// First WorkoutKit export supports only a faithfully representable
/// run/walk structure. Never silently drop a prescribed sensor target,
/// route, ghost, strength work or manual timing configuration.
enum ATHLTHWorkoutKitExportPolicy {
    static func canExport(_ recipe: WatchPreparedWorkoutTransfer) -> Bool {
        guard recipe.kind == .running || recipe.kind == .walking,
              recipe.routeID == nil, recipe.ghostRace == nil,
              recipe.strengthWorkout == nil, let workout = recipe.runningWorkout,
              !workout.steps.isEmpty, workout.steps.count <= 64,
              workout.intervalGhostConfiguration == nil, workout.soloGhostRace != true,
              workout.deferRouteUntilMain != true,
              workout.autoAdvanceTimedSteps != false,
              workout.targetAlerts?.heartRateEnabled != true,
              workout.targetAlerts?.paceAlertsEnabled != true,
              workout.treadmillInclinePercent == nil,
              workout.initialBeltSpeedKilometersPerHour == nil
        else { return false }
        var mainCount = 0
        for (index, step) in workout.steps.enumerated() {
            guard step.targetPaceMinSecondsPerKilometer == nil,
                  step.targetPaceMaxSecondsPerKilometer == nil,
                  step.targetHeartRateZone == nil,
                  step.targetHeartRatePercentMin == nil,
                  step.targetHeartRatePercentMax == nil,
                  step.targetTreadmillInclinePercent == nil,
                  step.ghostPaceSecondsPerKilometer == nil,
                  step.ghostFollowsRecovery != true
            else { return false }
            switch step.measure {
            case .time:
                guard let seconds = step.durationSeconds, seconds.isFinite,
                      (1...86400).contains(seconds) else { return false }
            case .distance:
                guard let meters = step.distanceMeters, meters.isFinite,
                      (1...200000).contains(meters) else { return false }
            case .open: break
            }
            switch step.phase?.lowercased() {
            case "warmup":
                guard index == 0, workout.autoStartMainAfterWarmup != false else { return false }
            case "cooldown":
                guard index == workout.steps.count - 1 else { return false }
            case nil, "work", "steady", "main", "recovery", "rest", "activerecovery":
                mainCount += 1
            default: return false
            }
        }
        return mainCount > 0
    }
}
