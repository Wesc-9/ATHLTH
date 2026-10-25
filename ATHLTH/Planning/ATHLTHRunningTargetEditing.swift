import Foundation

/// Preserve target dimensions that the compact editor does not expose.
/// Editing time, distance or notes must not erase an imported RPE or pace range.
enum ATHLTHRunningTargetEditing {
    static func preservingAdditionalTargets(
        from original: RunningStepTarget?, in edited: RunningStepTarget
    ) -> RunningStepTarget {
        guard let original else { return edited }
        var result = edited
        result.intensity.rpe = original.intensity.rpe
        if result.intensity.paceMinSecondsPerKilometer == original.intensity.paceMinSecondsPerKilometer,
           result.intensity.paceMaxSecondsPerKilometer == result.intensity.paceMinSecondsPerKilometer {
            result.intensity.paceMaxSecondsPerKilometer = original.intensity.paceMaxSecondsPerKilometer
        }
        if result.intensity.kind == .easy, original.intensity.kind == .rpe,
           original.intensity.rpe != nil {
            result.intensity.kind = .rpe
        }
        return result
    }
}
