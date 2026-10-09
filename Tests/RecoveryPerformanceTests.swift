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

    @MainActor
    func testCoachNeverAddsHealthMetricsWithoutPermission() throws {
        let original = makeContext(
            hrv: 75,
            recoveryPercent: 8,
            muscleStatus: "Fatigued"
        )
        let redacted = RecoveryAIContext.withoutHealthData

        XCTAssertEqual(original.hrvMilliseconds, 75)
        XCTAssertNil(redacted.recoveryScore)
        XCTAssertNil(redacted.sleepSeconds)
        XCTAssertNil(redacted.hrvMilliseconds)
        XCTAssertNil(redacted.restingHeartRate)
        XCTAssertNil(redacted.baselineSleepSeconds)
        XCTAssertNil(redacted.baselineHRVMilliseconds)
        XCTAssertNil(redacted.baselineRestingHeartRate)
        XCTAssertNil(redacted.chronicWeeklyAverageMinutes)
        XCTAssertTrue(redacted.muscles.isEmpty)
        XCTAssertNil(redacted.checkIn.stress)
        XCTAssertEqual(redacted.yesterdayTrainingMinutes, 0)
        XCTAssertEqual(redacted.acuteTrainingMinutes, 0)
        XCTAssertNotEqual(
            try RecoveryAIService.cacheSignature(for: original),
            try RecoveryAIService.cacheSignature(for: redacted)
        )
    }

    func testCoachFirstUseConsentIsOptionalAndAccountScoped() {
        let name = "ATHLTH.CoachConsentTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            XCTFail("Could not set up isolated test defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }

        let userA = UUID()
        let userB = UUID()
        XCTAssertNil(RecoveryCoachConsentPreferences.load(
            userID: userA, defaults: defaults
        ))
        XCTAssertNil(RecoveryCoachConsentPreferences.load(
            userID: userB, defaults: defaults
        ))

        let chatOnly = RecoveryCoachConsentPreferences.approve(
            userID: userA, healthSharingAllowed: false, defaults: defaults
        )
        XCTAssertFalse(chatOnly.healthSharingAllowed)
        XCTAssertNil(chatOnly.healthApprovedAt)
        XCTAssertNil(RecoveryCoachConsentPreferences.load(
            userID: userB, defaults: defaults
        ))

        let healthEnabled = RecoveryCoachConsentPreferences.approve(
            userID: userA, healthSharingAllowed: true, defaults: defaults
        )
        XCTAssertTrue(healthEnabled.healthSharingAllowed)
        XCTAssertEqual(healthEnabled.aiApprovedAt, chatOnly.aiApprovedAt)
        XCTAssertNotNil(healthEnabled.healthApprovedAt)

        let revokedHealth = RecoveryCoachConsentPreferences.approve(
            userID: userA, healthSharingAllowed: false, defaults: defaults
        )
        XCTAssertFalse(revokedHealth.healthSharingAllowed)
        XCTAssertNil(revokedHealth.healthApprovedAt)

        RecoveryCoachConsentPreferences.revoke(
            userID: userA, defaults: defaults
        )
        XCTAssertNil(RecoveryCoachConsentPreferences.load(
            userID: userA, defaults: defaults
        ))
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
