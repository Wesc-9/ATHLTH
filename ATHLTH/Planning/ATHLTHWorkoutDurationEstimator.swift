import Foundation

/// Planning-only estimate, never recorded as measured workout time.
/// Counts explicit pauses and per-set rest, and uses conservative averages
/// when a strength exercise has reps rather than a time target.
enum ATHLTHWorkoutDurationEstimator {
    static func minutes(for blocks: [WorkoutTemplateBlock]) -> Int? {
        guard !blocks.isEmpty else { return nil }
        let steps = blocks.expandedForExecution()
        guard steps.count <= 1_000 else { return nil }

        var seconds = 0.0
        var hasActivity = false

        for block in steps {
            switch block.kind {
            case .exercise:
                hasActivity = true
                if let time = block.durationSeconds, time > 0 {
                    seconds += time
                } else if let reps = block.repetitions, reps > 0 {
                    // Four seconds per repetition plus a short setup/transition.
                    seconds += Double(reps * 4 + 15)
                } else {
                    return nil
                }
            case .run:
                hasActivity = true
                if let time = block.durationSeconds, time > 0 {
                    seconds += time
                } else if let meters = block.distanceMeters,
                          let pace = block.targetPaceSecondsPerKilometer,
                          meters > 0, pace > 0 {
                    seconds += meters / 1_000 * pace
                } else {
                    // Unknown distance pace should not imply a precise duration.
                    return nil
                }
            case .rest:
                seconds += max(block.durationSeconds ?? 0, 0)
            case .note:
                if (block.wellnessKind != nil || block.activityTag == "cycling"),
                   let time = block.durationSeconds, time > 0 {
                    hasActivity = true
                    seconds += time
                }
            }
        }

        guard hasActivity, seconds > 0 else { return nil }
        let fiveMinuteBuckets = Int(ceil(seconds / 300))
        return min(max(fiveMinuteBuckets * 5, 5), 240)
    }
}
