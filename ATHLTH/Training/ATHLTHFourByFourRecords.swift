import Foundation

/// Personal, workout-level 4 × 4 benchmarks. They are not leaderboard
/// submissions: that still requires independently validated canonical plans.
/// Warm-up, recoveries and cool-down never increase the score.
enum ATHLTHFourByFourRecords {
    struct Result: Identifiable, Hashable {
        let id: UUID
        let date: Date
        let mainDistanceMeters: Double
        let mainSeconds: Double
        let fastestEffortSpeedKmh: Double
        let reported: Bool
        let exerciseCount: Int

        var averageSpeedKmh: Double {
            mainDistanceMeters * 3.6 / mainSeconds
        }

        var averagePaceSecondsPerKilometer: Double {
            mainSeconds * 1_000 / mainDistanceMeters
        }

        var fastestEffortPaceSecondsPerKilometer: Double {
            3_600 / fastestEffortSpeedKmh
        }
    }

    /// Require an actual completed four-by-four shape, not a title that merely
    /// says 4x4. The 2-minute rest must match; extending or skipping a rest
    /// makes the effort incomparable. Warm-up and cool-down can be extended.
    static func qualifyingResult(
        _ record: ATHLTHCompletedRunningPerformance
    ) -> Result? {
        qualifyingResult(
            steps: record.steps, id: record.id, date: record.completedAt
        )
    }

    static func qualifyingResult(
        steps: [ATHLTHRecordedRunningStep],
        id: UUID,
        date: Date
    ) -> Result? {
        let ordered = steps.sorted { $0.index < $1.index }
        let relevant = ordered.filter {
            !["warmup", "cooldown"].contains(($0.phase ?? "").lowercased())
        }
        guard relevant.count == 7 else { return nil }

        var mainDistance = 0.0
        var effortSpeeds: [Double] = []
        var reported = false
        for (index, step) in relevant.enumerated() {
            let phase = (step.phase ?? "").lowercased()
            guard step.activeSeconds.isFinite, step.distanceMeters.isFinite,
                  step.distanceMeters >= 0 else { return nil }

            if index.isMultiple(of: 2) {
                guard ["work", "main", "effort", "interval"].contains(phase),
                      abs(step.activeSeconds - 240) <= 2,
                      let speed = step.actualSpeedKilometersPerHour,
                      speed > 0 else { return nil }
                mainDistance += step.distanceMeters
                effortSpeeds.append(speed)
                reported = reported || step.isUserReported
            } else {
                guard ["recovery", "rest"].contains(phase),
                      abs(step.activeSeconds - 120) <= 2 else { return nil }
            }
        }

        guard effortSpeeds.count == 4, mainDistance > 0 else { return nil }
        return Result(
            id: id, date: date,
            mainDistanceMeters: mainDistance, mainSeconds: 960,
            fastestEffortSpeedKmh: effortSpeeds.max() ?? 0,
            reported: reported, exerciseCount: 4
        )
    }

    static func records(_ completed: [ATHLTHCompletedRunningPerformance]) -> [Result] {
        completed.compactMap(qualifyingResult)
            .sorted { $0.averagePaceSecondsPerKilometer < $1.averagePaceSecondsPerKilometer }
    }

    static func bestMeasured(_ completed: [ATHLTHCompletedRunningPerformance]) -> Result? {
        records(completed).first { !$0.reported }
    }

    static func bestReported(_ completed: [ATHLTHCompletedRunningPerformance]) -> Result? {
        records(completed).first { $0.reported }
    }
}
