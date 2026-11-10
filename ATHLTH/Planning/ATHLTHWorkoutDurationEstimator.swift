import Foundation

/// Planning-only estimate, never recorded as measured workout time.
/// Includes expanded interval rounds and between-set rests. A partial or
/// unbounded prescription must not appear as a complete workout duration.
enum ATHLTHWorkoutDurationEstimator {
    /// Exact-target estimate remains strict for recorded/executed workouts.
    static func minutes(for blocks: [WorkoutTemplateBlock]) -> Int? {
        calculateMinutes(for: blocks, fallbackPace: false)
    }

    /// Preview-only estimate when a distance-based run or walk lacks a
    /// personal pace target. These are assumptions, not measured performance:
    /// 6:00 min/km for running and 12:00 min/km for walking.
    static func previewMinutes(
        for blocks: [WorkoutTemplateBlock],
        defaultActivity: WorkoutCardioActivity = .running
    ) -> Int? {
        calculateMinutes(
            for: blocks, fallbackPace: true,
            defaultActivity: defaultActivity
        )
    }

    private static func calculateMinutes(
        for blocks: [WorkoutTemplateBlock],
        fallbackPace: Bool,
        defaultActivity: WorkoutCardioActivity = .running
    ) -> Int? {
        guard let seconds = calculateSeconds(
            for: blocks, fallbackPace: fallbackPace, defaultActivity: defaultActivity
        ) else { return nil }
        return max(Int(ceil(seconds / 300)) * 5, 5)
    }

    /// Precise seconds for the editor. Scheduling may still round to five
    /// minutes, but a 28:30 workout must never be presented as 30:00.
    static func previewSeconds(
        for blocks: [WorkoutTemplateBlock],
        defaultActivity: WorkoutCardioActivity = .running
    ) -> TimeInterval? {
        calculateSeconds(for: blocks, fallbackPace: true,
                         defaultActivity: defaultActivity)
    }

    /// Compact precise duration used in the workout builder and review.
    /// Display never rounds an interval up to a fictitious five-minute target.
    static func conciseDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "–" }
        let value = Int(seconds.rounded())
        let hours = value / 3_600
        let minutes = (value / 60) % 60
        let remainder = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        if value < 60 {
            return "\(value) " + ATHLTHLocalization.choose(
                english: "sec", norwegian: "sek"
            )
        }
        if remainder > 0 { return String(format: "%d:%02d", minutes, remainder) }
        return "\(minutes) min"
    }

    private static func calculateSeconds(
        for blocks: [WorkoutTemplateBlock],
        fallbackPace: Bool,
        defaultActivity: WorkoutCardioActivity = .running
    ) -> TimeInterval? {
        guard !blocks.isEmpty else { return nil }
        let steps = blocks.expandedForExecution()
        guard !steps.isEmpty, steps.count <= 1_000 else { return nil }

        var seconds = 0.0
        var hasActivity = false
        var countedTimedGroups = Set<UUID>()

        for block in steps {
            // EMOM has a fixed clock for each station; AMRAP has one fixed
            // workout cap. Repetition targets are *not* additional time.
            if let kind = block.executionGroupKind,
               kind.usesGroupClock,
               let id = block.executionGroupID {
                if countedTimedGroups.insert(id).inserted {
                    let allotted: TimeInterval
                    if kind == .emom {
                        allotted = (block.executionGroupClockSeconds ?? 60) *
                            Double(block.executionStationCount ?? 1) *
                            Double(block.executionTotalRounds ?? 1)
                    } else {
                        allotted = block.executionGroupClockSeconds ?? 720
                    }
                    guard allotted.isFinite && allotted > 0 else { return nil }
                    seconds += allotted
                    hasActivity = true
                }
                continue
            }
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
                          meters.isFinite, meters > 0 {
                    let pace = block.targetPaceSecondsPerKilometer ??
                        (fallbackPace
                            ? (block.cardioActivity ?? defaultActivity) == .walking
                                ? 720.0 : 360.0
                            : nil)
                    guard let pace, pace.isFinite, pace > 0 else {
                        return nil
                    }
                    seconds += meters / 1_000 * pace
                } else {
                    // Open-ended distance/time is never given a fake estimate.
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
        return seconds
    }
}
