import Foundation

/// Planning-only estimate, never recorded as measured workout time.
/// Includes expanded interval rounds and between-set rests. A partial or
/// unbounded prescription must not appear as a complete workout duration.
enum ATHLTHWorkoutDurationEstimator {
    static func minutes(for blocks: [WorkoutTemplateBlock]) -> Int? {
        guard !blocks.isEmpty else { return nil }
        let steps = blocks.expandedForExecution()
        guard !steps.isEmpty, steps.count <= 1_000 else { return nil }

        var seconds = 0.0
        var hasActivity = false

        for block in steps {
            switch block.kind {
            case .exercise:
                hasActivity = true
                if let time = block.durationSeconds, time.isFinite, time > 0 {
                    seconds += time
                } else if let reps = block.repetitions,
                          (1...10_000).contains(reps) {
                    // An approximate four seconds per repetition plus setup.
                    seconds += Double(reps) * 4 + 15
                } else {
                    return nil
                }
            case .run:
                hasActivity = true
                if let time = block.durationSeconds, time.isFinite, time > 0 {
                    seconds += time
                } else if let meters = block.distanceMeters,
                          let pace = block.targetPaceSecondsPerKilometer,
                          meters.isFinite, pace.isFinite,
                          meters > 0, pace > 0 {
                    seconds += meters / 1_000 * pace
                } else {
                    // Unknown distance or pace is NOT a known time target.
                    return nil
                }
            case .rest:
                // A pause without a time target is unbounded. Silently
                // treating it as zero understates the entire workout.
                guard let time = block.durationSeconds,
                      time.isFinite, time >= 0 else { return nil }
                seconds += time
            case .note:
                if block.wellnessKind != nil || block.activityTag == "cycling" {
                    // Timed cycling/yoga/recovery are real parts of the plan,
                    // not ignorable notes when duration is unspecified.
                    guard let time = block.durationSeconds,
                          time.isFinite, time > 0 else { return nil }
                    hasActivity = true
                    seconds += time
                }
                // Pure instructions are intentionally not assigned time.
            }
            guard seconds.isFinite, seconds >= 0 else { return nil }
        }

        // The existing plan model permits at most 240 minutes. Do not
        // misrepresent an over-limit timeline as exactly four hours.
        guard hasActivity, seconds > 0, seconds <= 240 * 60 else { return nil }
        return max(Int(ceil(seconds / 300)) * 5, 5)
    }
}
