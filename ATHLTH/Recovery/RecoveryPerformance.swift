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
            RecoveryDerivedSnapshot(
                statuses:
                    MuscleRecoveryEngine.statuses(
                        history: payload.history,
                        sorenessRatings:
                            payload.sorenessRatings,
                        activityLoad:
                            payload.activityLoad
                    ),
                unmappedExerciseNames:
                    MuscleRecoveryEngine
                        .unmappedExerciseNames(
                            history:
                                payload.history
                        )
            )
        }.value
    }
}
