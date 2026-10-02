import XCTest
@testable import ATHLTH

final class RecoveryReadinessEngineTests:
    XCTestCase {

    func testRequiresFiveCommonBaselineDays() {
        let now = Date()
        let days = baselineDays(
            count: 4,
            endingAt: now
        )

        let result =
            RecoveryReadinessEngine.evaluate(
                currentSleep:
                    SleepSummary(
                        totalAsleep: 8 * 3_600,
                        sleepEnd: now
                    ),
                currentHeart:
                    HeartSummary(
                        restingHeartRate: 60,
                        restingHeartRateDate: now,
                        hrvMilliseconds: 60,
                        hrvDate: now
                    ),
                sleepDays:
                    dictionary(
                        days,
                        value: 8 * 3_600
                    ),
                hrvDays:
                    dictionary(
                        days,
                        value: 60
                    ),
                restingHeartRateDays:
                    dictionary(
                        days,
                        value: 60
                    ),
                now: now
            )

        XCTAssertNil(result.score)
        XCTAssertEqual(
            result.state,
            .buildingBaseline
        )
        XCTAssertEqual(result.baselineDays, 4)
    }

    func testMatchingHealthyBaselineProducesReadyScore() throws {
        let now = Date()
        let days = baselineDays(
            count: 7,
            endingAt: now
        )

        let result =
            RecoveryReadinessEngine.evaluate(
                currentSleep:
                    SleepSummary(
                        totalAsleep: 8 * 3_600,
                        sleepEnd: now
                    ),
                currentHeart:
                    HeartSummary(
                        restingHeartRate: 60,
                        restingHeartRateDate: now,
                        hrvMilliseconds: 60,
                        hrvDate: now
                    ),
                sleepDays:
                    dictionary(
                        days,
                        value: 8 * 3_600
                    ),
                hrvDays:
                    dictionary(
                        days,
                        value: 60
                    ),
                restingHeartRateDays:
                    dictionary(
                        days,
                        value: 60
                    ),
                now: now
            )

        XCTAssertEqual(
            try XCTUnwrap(result.score),
            100
        )
        XCTAssertEqual(result.state, .ready)
        XCTAssertEqual(result.baselineDays, 7)
        XCTAssertEqual(
            try XCTUnwrap(
                result.averageSleepDuration
            ),
            8 * 3_600,
            accuracy: 0.001
        )
    }

    func testStaleHeartSignalsDoNotCreateReadinessScore() {
        let now = Date()
        let stale =
            now.addingTimeInterval(
                -(49 * 3_600)
            )
        let days = baselineDays(
            count: 7,
            endingAt: now
        )

        let result =
            RecoveryReadinessEngine.evaluate(
                currentSleep:
                    SleepSummary(
                        totalAsleep: 8 * 3_600,
                        sleepEnd: now
                    ),
                currentHeart:
                    HeartSummary(
                        restingHeartRate: 60,
                        restingHeartRateDate: stale,
                        hrvMilliseconds: 60,
                        hrvDate: stale
                    ),
                sleepDays:
                    dictionary(
                        days,
                        value: 8 * 3_600
                    ),
                hrvDays:
                    dictionary(
                        days,
                        value: 60
                    ),
                restingHeartRateDays:
                    dictionary(
                        days,
                        value: 60
                    ),
                now: now
            )

        XCTAssertNil(result.score)
        XCTAssertEqual(
            result.state,
            .buildingBaseline
        )
        XCTAssertEqual(result.baselineDays, 7)
    }

    func testInvalidSignalDayDoesNotCountTowardBaseline() {
        let now = Date()
        let days = baselineDays(
            count: 5,
            endingAt: now
        )

        var sleep =
            dictionary(
                days,
                value: 8 * 3_600
            )
        var hrv =
            dictionary(
                days,
                value: 60
            )
        var resting =
            dictionary(
                days,
                value: 60
            )

        if let invalidDay = days.first {
            hrv[invalidDay] = 0
            resting[invalidDay] =
                .nan
            sleep[invalidDay] =
                8 * 3_600
        }

        let result =
            RecoveryReadinessEngine.evaluate(
                currentSleep:
                    SleepSummary(
                        totalAsleep:
                            8 * 3_600,
                        sleepEnd: now
                    ),
                currentHeart:
                    HeartSummary(
                        restingHeartRate: 60,
                        restingHeartRateDate:
                            now,
                        hrvMilliseconds: 60,
                        hrvDate: now
                    ),
                sleepDays: sleep,
                hrvDays: hrv,
                restingHeartRateDays:
                    resting,
                now: now
            )

        XCTAssertNil(result.score)
        XCTAssertEqual(
            result.baselineDays,
            4
        )
        XCTAssertEqual(
            result.state,
            .buildingBaseline
        )
    }

    func testValidFiveDayBaselineStillProducesScore() throws {
        let now = Date()
        let days = baselineDays(
            count: 5,
            endingAt: now
        )

        let result =
            RecoveryReadinessEngine.evaluate(
                currentSleep:
                    SleepSummary(
                        totalAsleep:
                            7.5 * 3_600,
                        sleepEnd: now
                    ),
                currentHeart:
                    HeartSummary(
                        restingHeartRate: 60,
                        restingHeartRateDate:
                            now,
                        hrvMilliseconds: 60,
                        hrvDate: now
                    ),
                sleepDays:
                    dictionary(
                        days,
                        value:
                            7.5 * 3_600
                    ),
                hrvDays:
                    dictionary(
                        days,
                        value: 60
                    ),
                restingHeartRateDays:
                    dictionary(
                        days,
                        value: 60
                    ),
                now: now
            )

        XCTAssertNotNil(
            try XCTUnwrap(
                result.score
            )
        )
        XCTAssertEqual(
            result.baselineDays,
            5
        )
    }

    func testStaleSleepDoesNotCreateReadinessScore() {
        let now = Date()
        let staleSleep =
            now.addingTimeInterval(
                -(49 * 3_600)
            )
        let days = baselineDays(
            count: 7,
            endingAt: now
        )

        let result =
            RecoveryReadinessEngine.evaluate(
                currentSleep:
                    SleepSummary(
                        totalAsleep:
                            8 * 3_600,
                        sleepEnd:
                            staleSleep
                    ),
                currentHeart:
                    HeartSummary(
                        restingHeartRate: 60,
                        restingHeartRateDate:
                            now,
                        hrvMilliseconds: 60,
                        hrvDate: now
                    ),
                sleepDays:
                    dictionary(
                        days,
                        value: 8 * 3_600
                    ),
                hrvDays:
                    dictionary(
                        days,
                        value: 60
                    ),
                restingHeartRateDays:
                    dictionary(
                        days,
                        value: 60
                    ),
                now: now
            )

        XCTAssertNil(result.score)
        XCTAssertEqual(
            result.state,
            .buildingBaseline
        )
    }

    func testFutureHeartSignalsDoNotCreateReadinessScore() {
        let now = Date()
        let future =
            now.addingTimeInterval(60)
        let days = baselineDays(
            count: 7,
            endingAt: now
        )

        let result =
            RecoveryReadinessEngine.evaluate(
                currentSleep:
                    SleepSummary(
                        totalAsleep:
                            8 * 3_600,
                        sleepEnd: now
                    ),
                currentHeart:
                    HeartSummary(
                        restingHeartRate: 60,
                        restingHeartRateDate:
                            future,
                        hrvMilliseconds: 60,
                        hrvDate: future
                    ),
                sleepDays:
                    dictionary(
                        days,
                        value: 8 * 3_600
                    ),
                hrvDays:
                    dictionary(
                        days,
                        value: 60
                    ),
                restingHeartRateDays:
                    dictionary(
                        days,
                        value: 60
                    ),
                now: now
            )

        XCTAssertNil(result.score)
        XCTAssertEqual(
            result.state,
            .buildingBaseline
        )
    }

    private func baselineDays(
        count: Int,
        endingAt date: Date
    ) -> [Date] {
        let calendar = Calendar(
            identifier: .gregorian
        )
        let end =
            calendar.startOfDay(for: date)

        return (1...count).compactMap {
            calendar.date(
                byAdding: .day,
                value: -$0,
                to: end
            )
        }
    }

    private func dictionary(
        _ days: [Date],
        value: Double
    ) -> [Date: Double] {
        Dictionary(
            uniqueKeysWithValues:
                days.map { ($0, value) }
        )
    }
}


final class MuscleRecoveryLoadTests: XCTestCase {
    func testSameWorkoutCreatesLowerRelativeLoadWithEstablishedBaseline() {
        let now = Date()

        let newTrainer =
            MuscleRecoveryStatus(
                muscleGroup: "Quads",
                lastTrainedAt: now,
                completedSets: 6,
                runningMinutes: 30,
                estimatedRecoveryHours: 48,
                soreness: .none,
                baselineWeeklyStrengthSets: nil,
                chronicWeeklyTrainingMinutes: 60,
                acuteToChronicRatio: 1
            )

        let establishedTrainer =
            MuscleRecoveryStatus(
                muscleGroup: "Quads",
                lastTrainedAt: now,
                completedSets: 6,
                runningMinutes: 30,
                estimatedRecoveryHours: 48,
                soreness: .none,
                baselineWeeklyStrengthSets: 12,
                chronicWeeklyTrainingMinutes: 300,
                acuteToChronicRatio: 1
            )

        XCTAssertGreaterThan(
            newTrainer.loadScore,
            establishedTrainer.loadScore
        )
        XCTAssertGreaterThan(
            newTrainer.currentLoadScore,
            0.20
        )
        XCTAssertLessThan(
            establishedTrainer.currentLoadScore,
            newTrainer.currentLoadScore
        )
    }

    func testHighLoadFadesBackToReadyAsRecoveryWindowCompletes() {
        let recovered =
            MuscleRecoveryStatus(
                muscleGroup: "Quads",
                lastTrainedAt:
                    Date().addingTimeInterval(
                        -48 * 3_600
                    ),
                completedSets: 8,
                estimatedRecoveryHours: 48,
                soreness: .none,
                baselineWeeklyStrengthSets: nil,
                chronicWeeklyTrainingMinutes: 60,
                acuteToChronicRatio: 1
            )

        XCTAssertGreaterThanOrEqual(
            recovered.progress,
            0.99
        )
        XCTAssertLessThan(
            recovered.currentLoadScore,
            0.32
        )
    }

    func testHighSorenessKeepsAreaInPauseRange() {
        let sore =
            MuscleRecoveryStatus(
                muscleGroup: "Hamstrings",
                lastTrainedAt:
                    Date().addingTimeInterval(
                        -36 * 3_600
                    ),
                completedSets: 2,
                estimatedRecoveryHours: 48,
                soreness: .high,
                baselineWeeklyStrengthSets: 10,
                chronicWeeklyTrainingMinutes: 240,
                acuteToChronicRatio: 0.9
            )

        XCTAssertGreaterThanOrEqual(
            sore.currentLoadScore,
            0.78
        )
    }
}
