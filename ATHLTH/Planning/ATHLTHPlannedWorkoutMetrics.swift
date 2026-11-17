import Foundation

/// Read-only preview statistics for the advanced workout editor.
/// Never creates recorded distances or changes the saved workout recipe.
enum ATHLTHPlannedWorkoutMetrics {
    enum RunningLocation: Equatable {
        case outdoor, indoor, treadmill, mixed
    }

    static func runningLocation(for blocks: [WorkoutTemplateBlock]) -> RunningLocation? {
        let runs = blocks.filter { $0.kind == .run && !$0.isActiveRecovery }
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

    /// UI-only preview of the running/walking distance. In contrast to the
    /// strict target estimate above, fixed-time cardio steps may use a clearly
    /// marked illustrative pace when the athlete hasn't chosen a speed.
    /// Nothing here is written to Health, to the saved recipe, or to an
    /// actual workout result.
    struct DistancePreview: Equatable {
        let kilometers: Double
        let usesAssumedPace: Bool
        let usesEstimatedDistance: Bool
    }

    /// Zoned's Z6 is mapped to the ATHLTH five-zone system. A source range
    /// such as Z1–Z2 must survive even if targetHeartRateZone is nil.
    static func plannedHeartRateZoneRange(
        for blocks: [WorkoutTemplateBlock]
    ) -> ClosedRange<Int>? {
        var low = 6
        var high = 0
        for block in blocks {
            if let zone = block.targetHeartRateZone, (1...5).contains(zone) {
                low = min(low, zone)
                high = max(high, zone)
            }
            if let source = block.sourceIntensityZoneLabel {
                let values = source.split(whereSeparator: { !$0.isNumber })
                    .compactMap { Int($0) }
                if !values.isEmpty && values.allSatisfy({ (1...6).contains($0) }) {
                    for value in values {
                        low = min(low, min(value, 5))
                        high = max(high, min(value, 5))
                    }
                }
            }
            if let lower = block.targetHeartRatePercentMin,
               let upper = block.targetHeartRatePercentMax,
               lower.isFinite, upper.isFinite,
               lower >= 50, upper <= 100, upper >= lower {
                let start = min(5, max(1, Int(floor((lower - 50) / 10)) + 1))
                let end = min(5, max(1, Int(ceil((upper - 50) / 10))))
                low = min(low, start)
                high = max(high, end)
            }
        }
        return high > 0 && low <= high ? low...high : nil
    }

    /// Conservative pace assumptions, only for planning previews. They are
    /// never prescribed to the athlete. A 3-minute hard test is not assumed
    /// to be run at the same speed as a recovery walk.
    static func fallbackPaceSecondsPerKilometer(
        for step: WorkoutTemplateBlock,
        defaultActivity: WorkoutCardioActivity = .running
    ) -> Double {
        if (step.cardioActivity ?? defaultActivity) == .walking {
            return 720
        }
        if step.isActiveRecovery { return 540 }
        let title = step.title.lowercased()
        if title.contains("gå, deretter") || title.contains("walking then") ||
            title.contains("walk then") || title.contains("walk 3min") {
            return 600
        }
        if let range = plannedHeartRateZoneRange(for: [step]) {
            switch range.lowerBound {
            case 1: return range.upperBound > 1 ? 420 : 450
            case 2: return 390
            case 3: return 345
            case 4: return 300
            default: return 270
            }
        }
        return 360
    }

    static func previewDistance(
        for blocks: [WorkoutTemplateBlock],
        defaultActivity: WorkoutCardioActivity = .running
    ) -> DistancePreview? {
        guard !blocks.isEmpty else { return nil }
        let steps = blocks.expandedForExecution()
        guard !steps.isEmpty, steps.count <= 1_000 else { return nil }
        var totalMeters = 0.0
        var assumed = false
        var estimatedDistance = false
        var hasMovement = false

        for step in steps {
            if step.kind == .note && step.activityTag == "cycling" {
                // Do not report a total workout distance that omits cycling.
                return nil
            }
            let active = step.kind == .run ||
                (step.kind == .rest &&
                 (step.targetPaceSecondsPerKilometer != nil ||
                  step.activityTag == "active_recovery"))
            guard active else { continue }

            if let prescribed = step.targetPaceSecondsPerKilometer,
               (!prescribed.isFinite || !(120...3_600).contains(prescribed)) {
                return nil
            }

            if let meters = step.distanceMeters {
                // Explicit distances are known; don't invent a pace merely
                // because the athlete hasn't selected a tempo target.
                guard meters.isFinite, meters > 0 else { return nil }
                if let seconds = step.durationSeconds {
                    guard seconds.isFinite, seconds > 0 else { return nil }
                }
                totalMeters += meters
                hasMovement = true
            } else if let seconds = step.durationSeconds {
                guard seconds.isFinite, seconds > 0 else { return nil }
                let pace: Double
                if let prescribed = step.targetPaceSecondsPerKilometer {
                    pace = prescribed
                } else {
                    // Internal estimate only; never expose this as a
                    // user-selected target pace or measured result.
                    assumed = true
                    pace = fallbackPaceSecondsPerKilometer(
                        for: step, defaultActivity: defaultActivity
                    )
                }
                totalMeters += seconds * 1_000 / pace
                estimatedDistance = true
                hasMovement = true
            } else {
                // No bounded time or distance means no meaningful estimate.
                return nil
            }
            guard totalMeters.isFinite, totalMeters > 0 else { return nil }
        }

        guard hasMovement else { return nil }
        return DistancePreview(
            kilometers: totalMeters / 1_000,
            usesAssumedPace: assumed,
            usesEstimatedDistance: estimatedDistance
        )
    }

    /// Show one pace/speed only if every running segment has the same target.
    /// Mixed-effort intervals should never be labeled with a misleading pace.
    static func commonPaceSecondsPerKilometer(
        for blocks: [WorkoutTemplateBlock]
    ) -> Double? {
        let runs = blocks.filter { $0.kind == .run && !$0.isActiveRecovery }
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
        let targets = blocks.filter { $0.kind == .run && !$0.isActiveRecovery }
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
