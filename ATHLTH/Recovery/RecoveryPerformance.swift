import Foundation

struct RecoveryDerivedSnapshot: @unchecked Sendable {
    let statuses: [MuscleRecoveryStatus]
    let unmappedExerciseNames: [String]

    static let empty = RecoveryDerivedSnapshot(
        statuses: [],
        unmappedExerciseNames: []
    )
}

private struct RecoveryComputationPayload: @unchecked Sendable {
    let history: [StrengthWorkoutLog]
    let sorenessRatings: [String: RecoverySorenessLevel]
    let activityLoad: RecoveryTrainingLoadSummary
}

enum RecoveryDerivedSnapshotBuilder {
    static func build(
        history: [StrengthWorkoutLog],
        sorenessRatings: [String: RecoverySorenessLevel],
        activityLoad: RecoveryTrainingLoadSummary
    ) async -> RecoveryDerivedSnapshot {
        let payload = RecoveryComputationPayload(
            history: history,
            sorenessRatings: sorenessRatings,
            activityLoad: activityLoad
        )
        let performanceID =
            ATHLTHPerformance.begin("RecoveryDerivedCompute")
        defer {
            ATHLTHPerformance.end(
                "RecoveryDerivedCompute",
                id: performanceID
            )
        }

        return await Task.detached(
            priority: .userInitiated
        ) {
            let baselineStart =
                Date().addingTimeInterval(
                    -35 * 86_400
                )

            // StrengthWorkoutStore keeps history newest-first.
            // Stop as soon as we reach data older than the recovery
            // baseline instead of walking the user's full workout archive.
            let recentHistory =
                Array(
                    payload.history
                        .prefix {
                            $0.startedAt >=
                                baselineStart
                        }
                )
                .filter(\.isFinished)

            return RecoveryDerivedSnapshot(
                statuses:
                    MuscleRecoveryEngine.statuses(
                        history: recentHistory,
                        sorenessRatings:
                            payload.sorenessRatings,
                        activityLoad:
                            payload.activityLoad
                    ),
                unmappedExerciseNames:
                    MuscleRecoveryEngine
                        .unmappedExerciseNames(
                            history:
                                recentHistory
                        )
            )
        }.value
    }
}
