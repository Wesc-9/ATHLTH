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
                        totalAsleep: 8 * 3_600
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
                        totalAsleep: 8 * 3_600
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
                        totalAsleep: 8 * 3_600
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
