import Foundation

/// Comparable interval-exercise history derived ONLY from finished,
/// measured run segments. A planned pace, distance or HR target can never
/// create an achieved result or personal best.
enum ATHLTHCompoundExerciseProgress {
    struct Result: Identifiable, Hashable {
        let id: UUID
        let date: Date
        let source: String
        let protocolID: String
        let workSeconds: TimeInterval
        let workDistanceMeters: Double
        let efforts: Int
        let reported: Bool
        let recoverySeconds: TimeInterval

        var averageWorkSpeedKmh: Double {
            workDistanceMeters * 3.6 / workSeconds
        }
    }

    private static func isRecovery(_ recorded: ATHLTHRecordedRunningStep) -> Bool {
        ["rest", "recovery"].contains((recorded.phase ?? "").lowercased())
    }

    private static func workPhase(_ recorded: ATHLTHRecordedRunningStep) -> Bool {
        ["work", "main", "effort", "interval"].contains(
            (recorded.phase ?? "").lowercased()
        )
    }

    private static func expectedProtocol(
        _ exercise: ATHLTHCompoundExercise
    ) -> [WorkoutTemplateBlock] {
        exercise.blocks.filter {
            $0.kind == .run || $0.kind == .rest
        }
    }

    private static func match(
        _ expected: [WorkoutTemplateBlock],
        _ recorded: [ATHLTHRecordedRunningStep]
    ) -> Bool {
        guard expected.count == recorded.count else { return false }
        for (block, actual) in zip(expected, recorded) {
            guard actual.activeSeconds.isFinite, actual.activeSeconds >= 10,
                  actual.distanceMeters.isFinite, actual.distanceMeters >= 0 else {
                return false
            }
            if block.isRestOrActiveRecovery {
                guard isRecovery(actual) else { return false }
                if let seconds = block.durationSeconds {
                    guard abs(actual.activeSeconds - seconds) <=
                        max(5, seconds * 0.07) else { return false }
                }
            } else {
                guard block.kind == .run, workPhase(actual),
                      actual.actualSpeedKilometersPerHour != nil else { return false }
                if let seconds = block.durationSeconds {
                    guard abs(actual.activeSeconds - seconds) <=
                        max(3, seconds * 0.03) else { return false }
                }
                if let meters = block.distanceMeters {
                    guard abs(actual.distanceMeters - meters) <=
                        max(15, meters * 0.035) else { return false }
                }
            }
        }
        return true
    }

    /// A compound exercise can appear inside another session. A single
    /// unambiguous contiguous match counts; multiple matches in one recording
    /// are not silently merged into a single fabricated personal best.
    static func result(
        for exercise: ATHLTHCompoundExercise,
        in record: ATHLTHCompletedRunningPerformance
    ) -> Result? {
        result(
            for: exercise, steps: record.steps,
            id: record.id, date: record.completedAt, source: record.source
        )
    }

    /// Direct evidence matcher also allows fixture tests without creating a
    /// synthetic HealthKit workout. Never substitute planned targets here.
    static func result(
        for exercise: ATHLTHCompoundExercise,
        steps: [ATHLTHRecordedRunningStep],
        id: UUID,
        date: Date,
        source: String
    ) -> Result? {
        let expected = expectedProtocol(exercise)
        // GPS elevation/grade evidence is not present in recorded step
        // summaries. Matching a hill session by time alone could produce
        // a false hill PR from an unrelated flat interval workout.
        guard exercise.category != .hills,
              !expected.contains(where: {
                  $0.targetGradientPercent != nil ||
                  $0.targetElevationGainMeters != nil
              }),
              exercise.isRunning, expected.count >= 2,
              expected.contains(where: {
                  $0.kind == .run && !$0.isActiveRecovery
              }) else { return nil }
        let actual = steps.sorted { $0.index < $1.index }.filter {
            !["warmup", "cooldown"].contains(($0.phase ?? "").lowercased())
        }
        guard actual.count >= expected.count else { return nil }
        var matching: [[ATHLTHRecordedRunningStep]] = []
        for offset in 0...(actual.count - expected.count) {
            let sample = Array(actual[offset..<(offset + expected.count)])
            if match(expected, sample) { matching.append(sample) }
        }
        guard matching.count == 1, let steps = matching.first else { return nil }
        let work = steps.filter { !isRecovery($0) }
        let seconds = work.reduce(0) { $0 + $1.activeSeconds }
        let distance = work.reduce(0) { $0 + $1.distanceMeters }
        guard seconds > 0, distance > 0, seconds.isFinite, distance.isFinite else {
            return nil
        }
        return Result(
            id: id, date: date, source: source,
            protocolID: exercise.protocolID,
            workSeconds: seconds, workDistanceMeters: distance,
            efforts: work.count,
            reported: work.contains { $0.isUserReported },
            recoverySeconds: steps.filter(isRecovery)
                .reduce(0) { $0 + $1.activeSeconds }
        )
    }

    static func results(
        for exercise: ATHLTHCompoundExercise,
        completed: [ATHLTHCompletedRunningPerformance]
    ) -> [Result] {
        completed.compactMap { result(for: exercise, in: $0) }
            .sorted { $0.date > $1.date }
    }

    static func bestMeasured(_ results: [Result]) -> Result? {
        results.filter { !$0.reported }
            .max { $0.averageWorkSpeedKmh < $1.averageWorkSpeedKmh }
    }

    static func bestReported(_ results: [Result]) -> Result? {
        results.filter(\.reported)
            .max { $0.averageWorkSpeedKmh < $1.averageWorkSpeedKmh }
    }
}
