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

    func testCoachContinuousHealthSharingStaysOffUntilComplianceRelease() {
        let suite = "ATHLTH.CoachHealthV2.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Unable to create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let user = UUID()
        let otherUser = UUID()

        // Neither preexisting HealthKit access nor new chat consent opts
        // users into ongoing external transfer.
        XCTAssertEqual(
            RecoveryCoachHealthSharingPreferences.effectiveMode(
                userID: user, defaults: defaults
            ), .off
        )
        _ = RecoveryCoachConsentPreferences.approve(
            userID: user, healthSharingAllowed: true, defaults: defaults
        )
        XCTAssertEqual(
            RecoveryCoachHealthSharingPreferences.effectiveMode(
                userID: user, defaults: defaults
            ), .confirmEveryQuestion
        )
        XCTAssertFalse(
            RecoveryCoachHealthSharingPreferences.canAutomaticallyShare(
                userID: user, defaults: defaults
            )
        )

        // A bypassed/modified interface still cannot activate automation.
        let attempted = RecoveryCoachHealthSharingPreferences.save(
            userID: user, requestedMode: .automatic, defaults: defaults
        )
        XCTAssertEqual(attempted.mode, .confirmEveryQuestion)
        XCTAssertNil(attempted.automaticConsentAt)
        XCTAssertFalse(
            RecoveryCoachHealthSharingPreferences.canAutomaticallyShare(
                userID: user, defaults: defaults
            )
        )
        XCTAssertEqual(
            RecoveryCoachHealthSharingPreferences.effectiveMode(
                userID: otherUser, defaults: defaults
            ), .off
        )

        _ = RecoveryCoachHealthSharingPreferences.save(
            userID: user, requestedMode: .off, defaults: defaults
        )
        XCTAssertEqual(
            RecoveryCoachHealthSharingPreferences.effectiveMode(
                userID: user, defaults: defaults
            ), .off
        )
        _ = RecoveryCoachHealthSharingPreferences.save(
            userID: user, requestedMode: .confirmEveryQuestion,
            defaults: defaults
        )
        XCTAssertEqual(
            RecoveryCoachHealthSharingPreferences.effectiveMode(
                userID: user, defaults: defaults
            ), .confirmEveryQuestion
        )

        RecoveryCoachConsentPreferences.revoke(userID: user, defaults: defaults)
        XCTAssertNil(RecoveryCoachHealthSharingPreferences.load(
            userID: user, defaults: defaults
        ))
        XCTAssertEqual(
            RecoveryCoachHealthSharingPreferences.effectiveMode(
                userID: user, defaults: defaults
            ), .off
        )
    }

    func testInsightsAIRequiresSeparateExplicitAccountConsent() {
        let name = "ATHLTH.InsightsConsentTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            return XCTFail("Unable to create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: name) }

        let first = UUID()
        let second = UUID()

        // Legacy general AI/HealthKit settings never migrate silently.
        defaults.set(
            true,
            forKey: AccountLocalStorage.key(
                "aiHealthDataConsent",
                userID: first
            )
        )
        XCTAssertNil(
            RecoveryInsightAIConsentPreferences.load(
                userID: first, defaults: defaults
            )
        )
        XCTAssertFalse(
            RecoveryInsightAIConsentPreferences.isAuthorized(
                userID: first, defaults: defaults
            )
        )

        // Declining is remembered and does not affect local insights.
        let declined = RecoveryInsightAIConsentPreferences.decide(
            userID: first,
            allowExternalHealthProcessing: false,
            defaults: defaults
        )
        XCTAssertFalse(declined.allowsExternalHealthProcessing)
        XCTAssertFalse(
            RecoveryInsightAIConsentPreferences.isAuthorized(
                userID: first, defaults: defaults
            )
        )

        let approved = RecoveryInsightAIConsentPreferences.decide(
            userID: first,
            allowExternalHealthProcessing: true,
            defaults: defaults
        )
        XCTAssertTrue(approved.allowsExternalHealthProcessing)
        XCTAssertFalse(
            RecoveryInsightAIConsentPreferences.isAuthorized(
                userID: second, defaults: defaults
            )
        )

        // Withdrawal clears any cached AI health insight immediately.
        defaults.set(
            Data("Sensitive response".utf8),
            forKey: "athlth.recoveryAIInsight.\(first.uuidString).nb"
        )
        let withdrawn = RecoveryInsightAIConsentPreferences.decide(
            userID: first,
            allowExternalHealthProcessing: false,
            defaults: defaults
        )
        XCTAssertFalse(withdrawn.allowsExternalHealthProcessing)
        XCTAssertNil(
            defaults.data(
                forKey: "athlth.recoveryAIInsight.\(first.uuidString).nb"
            )
        )

        RecoveryInsightAIConsentPreferences.removeForDeletedAccount(
            userID: first,
            defaults: defaults
        )
        XCTAssertNil(
            RecoveryInsightAIConsentPreferences.load(
                userID: first, defaults: defaults
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
