import XCTest
@testable import ATHLTH

final class MuscleRecoveryLoadTests: XCTestCase {
    func testShortRunStaysLowLoadAndMostlyReady() {
        let status =
            MuscleRecoveryStatus(
                muscleGroup: "Calves",
                lastTrainedAt: Date(),
                completedSets: 0,
                runningMinutes: 20,
                walkingMinutes: 0,
                estimatedRecoveryHours: 16,
                soreness: .none
            )

        XCTAssertLessThan(
            status.currentLoadScore,
            0.20
        )
        XCTAssertGreaterThan(
            status.readinessScore,
            0.80
        )
        XCTAssertEqual(
            status.loadTitle,
            ATHLTHLocalization.choose(
                english: "Ready",
                norwegian: "Klar"
            )
        )
    }

    func testVeryShortStrengthSessionDoesNotCreateHighLoad() {
        let status =
            MuscleRecoveryStatus(
                muscleGroup: "Quads",
                lastTrainedAt: Date(),
                completedSets: 1,
                strengthMinutes: 5,
                estimatedRecoveryHours: 8,
                soreness: .none
            )

        XCTAssertLessThan(
            status.currentLoadScore,
            0.20
        )
        XCTAssertGreaterThan(
            status.readinessScore,
            0.80
        )
    }

    func testLongStrengthSessionCanCreateMeaningfulLoad() {
        let status =
            MuscleRecoveryStatus(
                muscleGroup: "Quads",
                lastTrainedAt: Date(),
                completedSets: 10,
                strengthMinutes: 60,
                estimatedRecoveryHours: 42,
                soreness: .none
            )

        XCTAssertGreaterThan(
            status.currentLoadScore,
            0.60
        )
        XCTAssertLessThan(
            status.readinessScore,
            0.40
        )
    }

    func testRedThresholdRequiresVeryHighRecentLoad() {
        let moderate =
            MuscleRecoveryStatus(
                muscleGroup: "Calves",
                lastTrainedAt: Date(),
                completedSets: 0,
                runningMinutes: 90,
                estimatedRecoveryHours: 40,
                soreness: .none
            )

        let veryHigh =
            MuscleRecoveryStatus(
                muscleGroup: "Calves",
                lastTrainedAt: Date(),
                completedSets: 0,
                runningMinutes: 180,
                estimatedRecoveryHours: 52,
                soreness: .none
            )

        XCTAssertLessThan(
            moderate.currentLoadScore,
            0.84
        )
        XCTAssertGreaterThanOrEqual(
            veryHigh.currentLoadScore,
            0.84
        )
    }
}
