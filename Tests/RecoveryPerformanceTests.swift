import XCTest
@testable import ATHLTH

final class RecoveryPerformanceTests:
    XCTestCase {
    func testSnapshotSorenessInputBuildsStatusWithoutStoreAccess() {
        let statuses =
            MuscleRecoveryEngine.statuses(
                history: [],
                sorenessRatings: [
                    "Quads": .moderate
                ],
                activityLoad:
                    RecoveryTrendSnapshot
                        .empty
                        .trainingLoad
            )

        XCTAssertEqual(
            statuses.first {
                $0.muscleGroup ==
                    "Quads"
            }?.soreness,
            .moderate
        )
    }

    func testDerivedSnapshotBuilderRunsWithImmutableInputs() async {
        let snapshot =
            await RecoveryDerivedSnapshotBuilder
                .build(
                    history: [],
                    sorenessRatings: [
                        "Calves": .mild
                    ],
                    activityLoad:
                        RecoveryTrendSnapshot
                            .empty
                            .trainingLoad
                )

        XCTAssertEqual(
            snapshot.statuses.first {
                $0.muscleGroup ==
                    "Calves"
            }?.soreness,
            .mild
        )
    }

    @MainActor
    func testAICacheSignatureIgnoresPassiveMuscleRecoveryProgress() throws {
        let base =
            makeContext(
                hrv: 55,
                recoveryPercent: 45,
                muscleStatus: "Recovering"
            )
        let timeProgressed =
            makeContext(
                hrv: 55,
                recoveryPercent: 62,
                muscleStatus: "Ready soon"
            )

        XCTAssertEqual(
            try RecoveryAIService
                .cacheSignature(
                    for: base
                ),
            try RecoveryAIService
                .cacheSignature(
                    for: timeProgressed
                )
        )
    }

    @MainActor
    func testAICacheSignatureChangesWhenHealthSignalChanges() throws {
        let first =
            makeContext(
                hrv: 55,
                recoveryPercent: 45,
                muscleStatus: "Recovering"
            )
        let changed =
            makeContext(
                hrv: 61,
                recoveryPercent: 45,
                muscleStatus: "Recovering"
            )

        XCTAssertNotEqual(
            try RecoveryAIService
                .cacheSignature(
                    for: first
                ),
            try RecoveryAIService
                .cacheSignature(
                    for: changed
                )
        )
    }

    private func makeContext(
        hrv: Double,
        recoveryPercent: Int,
        muscleStatus: String
    ) -> RecoveryAIContext {
        RecoveryAIContext(
            recoveryScore: 76,
            recoveryState: "Balanced",
            recoveryDetail:
                "Stable recovery",
            sleepSeconds: 27_000,
            baselineSleepSeconds:
                26_400,
            hrvMilliseconds: hrv,
            baselineHRVMilliseconds:
                54,
            restingHeartRate: 51,
            baselineRestingHeartRate:
                52,
            yesterdayTrainingMinutes:
                45,
            acuteTrainingMinutes: 210,
            chronicWeeklyAverageMinutes:
                195,
            muscles: [
                RecoveryAIMuscleInput(
                    name: "Quads",
                    recoveryPercent:
                        recoveryPercent,
                    status: muscleStatus,
                    completedSets: 8
                )
            ],
            checkIn:
                RecoveryAICheckIn(
                    energy: 4,
                    stress: 2,
                    overallSoreness: 2,
                    motivation: 4
                )
        )
    }
}
