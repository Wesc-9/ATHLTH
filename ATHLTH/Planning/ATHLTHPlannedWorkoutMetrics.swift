import Foundation

/// Read-only preview statistics for the advanced workout editor.
/// Never creates recorded distances or changes the saved workout recipe.
enum ATHLTHPlannedWorkoutMetrics {
    enum RunningLocation: Equatable {
        case outdoor, indoor, treadmill, mixed
    }

    static func runningLocation(for blocks: [WorkoutTemplateBlock]) -> RunningLocation? {
        let runs = blocks.filter { $0.kind == .run }
        guard !runs.isEmpty else { return nil }
        if runs.allSatisfy({
            $0.isIndoor == true && $0.treadmillInclinePercent != nil
        }) {
            return .treadmill
        }
        if runs.allSatisfy({ $0.isIndoor == true }) {
            return .indoor
        }
        if runs.allSatisfy({ $0.isIndoor != true }) {
            return .outdoor
        }
        return .mixed
    }

    /// Time-based distances require a real target pace. Unknown run targets
    /// invalidate the total rather than displaying an incomplete distance.
    /// An untargeted rest is stationary; a paced recovery can add distance.
    static func estimatedDistanceKilometers(
        for blocks: [WorkoutTemplateBlock]
    ) -> Double? {
        guard !blocks.isEmpty else { return nil }
        let steps = blocks.expandedForExecution()
        guard steps.count <= 1_000 else { return nil }
        var totalMeters = 0.0
        var hasMovement = false

        for step in steps where step.kind == .run || step.kind == .rest {
            if let meters = step.distanceMeters {
                guard meters.isFinite, meters > 0 else { return nil }
                totalMeters += meters
                hasMovement = true
            } else if let seconds = step.durationSeconds,
                      let pace = step.targetPaceSecondsPerKilometer {
                guard seconds.isFinite, seconds > 0,
                      pace.isFinite, pace > 0 else { return nil }
                totalMeters += seconds * 1_000 / pace
                hasMovement = true
            } else if step.kind == .run {
                // Time without target speed, or an open-ended run.
                return nil
            } else if step.activityTag == "active_recovery" {
                // Never silently count an explicitly active recovery as still.
                return nil
            }
            guard totalMeters.isFinite else { return nil }
        }
        return hasMovement && totalMeters > 0 ? totalMeters / 1_000 : nil
    }

    /// Show one pace/speed only if every running segment has the same target.
    /// Mixed-effort intervals should never be labeled with a misleading pace.
    static func commonPaceSecondsPerKilometer(
        for blocks: [WorkoutTemplateBlock]
    ) -> Double? {
        let runs = blocks.filter { $0.kind == .run }
        guard !runs.isEmpty,
              let pace = runs.first?.targetPaceSecondsPerKilometer,
              pace.isFinite, pace > 0,
              runs.allSatisfy({
                  guard let other = $0.targetPaceSecondsPerKilometer else {
                      return false
                  }
                  return other.isFinite && other > 0 && abs(other - pace) < 0.5
              }) else { return nil }
        return pace
    }

    static func hasVariablePace(for blocks: [WorkoutTemplateBlock]) -> Bool {
        let targets = blocks.filter { $0.kind == .run }
            .compactMap(\.targetPaceSecondsPerKilometer)
            .filter { $0.isFinite && $0 > 0 }
        guard let first = targets.first else { return false }
        return targets.contains { abs($0 - first) >= 0.5 }
    }

    static func treadmillInclineRange(
        for blocks: [WorkoutTemplateBlock]
    ) -> ClosedRange<Double>? {
        let slopes = blocks.filter { $0.kind == .run }
            .compactMap(\.treadmillInclinePercent)
            .filter { $0.isFinite && $0 >= 0 }
        guard let minimum = slopes.min(), let maximum = slopes.max() else {
            return nil
        }
        return minimum...maximum
    }
}
