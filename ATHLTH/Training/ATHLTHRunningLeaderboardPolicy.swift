import Foundation

/// Local evidence gate for an exact, published running challenge structure.
/// This is intentionally NOT a public leaderboard submission: the server must
/// independently validate the canonical template/version and source evidence.
enum ATHLTHRunningLeaderboardPolicy {
    struct Verdict: Hashable {
        let eligible: Bool
        let reason: String?
        let mainDistanceMeters: Double
        let mainActiveSeconds: TimeInterval

        var mainSpeedKilometersPerHour: Double? {
            guard eligible, mainActiveSeconds > 0 else { return nil }
            return mainDistanceMeters * 3.6 / mainActiveSeconds
        }
    }

    /// Compare the executed recipe to the immutable published challenge,
    /// not to an athlete-edited copy. Target pace may vary, but changing
    /// effort/rest structure or treadmill incline changes the competition.
    static func evaluate(
        canonical: WatchRunningWorkoutTransfer,
        executed: WatchRunningWorkoutTransfer,
        recorded: [ATHLTHRecordedRunningStep],
        modifiedDuringWorkout: Bool = false
    ) -> Verdict {
        guard matchesCanonicalStructure(canonical, executed) else {
            return Verdict(
                eligible: false,
                reason: "The workout differs from the published challenge.",
                mainDistanceMeters: 0, mainActiveSeconds: 0
            )
        }
        return evaluate(
            planned: canonical, recorded: recorded,
            modifiedDuringWorkout: modifiedDuringWorkout
        )
    }

    private static func matchesCanonicalStructure(
        _ canonical: WatchRunningWorkoutTransfer,
        _ executed: WatchRunningWorkoutTransfer
    ) -> Bool {
        guard !canonical.steps.isEmpty,
              canonical.steps.count == executed.steps.count else { return false }
        if let officialID = canonical.sourceWorkoutID,
           officialID != executed.sourceWorkoutID { return false }
        return zip(canonical.steps, executed.steps).allSatisfy { original, actual in
            original.phase?.lowercased() == actual.phase?.lowercased() &&
            original.measure == actual.measure &&
            original.durationSeconds == actual.durationSeconds &&
            original.distanceMeters == actual.distanceMeters &&
            original.targetTreadmillInclinePercent ==
                actual.targetTreadmillInclinePercent
        }
    }

    static func evaluate(
        planned: WatchRunningWorkoutTransfer,
        recorded: [ATHLTHRecordedRunningStep],
        modifiedDuringWorkout: Bool = false
    ) -> Verdict {
        func rejected(_ reason: String) -> Verdict {
            Verdict(eligible: false, reason: reason,
                    mainDistanceMeters: 0, mainActiveSeconds: 0)
        }

        guard !modifiedDuringWorkout else {
            return rejected("The planned workout was modified during recording.")
        }
        guard !planned.steps.isEmpty,
              recorded.count == planned.steps.count,
              Set(recorded.map(\.index)) == Set(planned.steps.indices)
        else { return rejected("A phase is missing or the workout was not completed.") }

        let ordered = recorded.sorted { $0.index < $1.index }
        var meters = 0.0
        var seconds = 0.0
        var mainCount = 0

        for (index, step) in planned.steps.enumerated() {
            let actual = ordered[index]
            guard actual.index == index,
                  actual.phase?.lowercased() == step.phase?.lowercased(),
                  actual.activeSeconds.isFinite, actual.activeSeconds >= 0,
                  actual.distanceMeters.isFinite, actual.distanceMeters >= 0,
                  !actual.isUserReported else {
                return rejected("Recorded phases or evidence do not match the template.")
            }
            let phase = step.phase?.lowercased() ?? ""
            // Warm-up and cool-down may exceed the planned time. They
            // contribute neither distance nor time to the score.
            if phase == "warmup" || phase == "cooldown" { continue }
            // All work and recovery durations must match the registered
            // structure. A shortened drag or extended rest is unranked.
            switch step.measure {
            case .time:
                guard let prescribed = step.durationSeconds,
                      prescribed > 0,
                      abs(actual.activeSeconds - prescribed) <= 2 else {
                    return rejected("A work or recovery duration was changed.")
                }
            case .distance:
                guard let prescribed = step.distanceMeters,
                      prescribed > 0,
                      actual.distanceMeters >= prescribed - 10 else {
                    return rejected("A work or recovery distance was changed.")
                }
            case .open:
                return rejected("Open-ended main phases cannot be ranked fairly.")
            }

            if phase == "recovery" || phase == "rest" {
                continue
            }
            mainCount += 1
            meters += actual.distanceMeters
            seconds += actual.activeSeconds
        }

        guard mainCount > 0, meters > 0, seconds > 0,
              meters.isFinite, seconds.isFinite else {
            return rejected("No measurable main running section.")
        }
        return Verdict(eligible: true, reason: nil,
                       mainDistanceMeters: meters,
                       mainActiveSeconds: seconds)
    }
}
