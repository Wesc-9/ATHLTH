import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHInsightsRunComparisonTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_790_000_000)

    private func run(
        daysAgo: Double,
        minutes: Double = 40,
        heart: Double? = 150,
        power: Double? = 265,
        speed: Double? = 11.0,
        calculatedSpeed: Bool = false
    ) -> ATHLTHInsightsRunPerformanceSession {
        ATHLTHInsightsRunPerformanceSession(
            id: UUID(),
            endDate: baseDate.addingTimeInterval(-daysAgo * 86_400),
            durationMinutes: minutes,
            averageHeartRateBPM: heart,
            averageRunningPowerWatts: power,
            averageSpeedKPH: speed,
            speedFromDistance: calculatedSpeed
        )
    }

    func testComparesPulseAndPowerAtSimilarSpeedFromSeparateRealWorkouts() {
        let latest = run(daysAgo: 0, heart: 146, power: 257, speed: 11.2)
        let previous = run(daysAgo: 10, heart: 154, power: 273, speed: 11.0)
        let unrelated = run(daysAgo: 2, heart: 165, power: 320, speed: 14.0)

        let actual = ATHLTHInsightsRunComparisonPolicy.closestComparable(
            to: latest,
            among: [unrelated, previous, latest]
        )
        XCTAssertEqual(actual?.previous.id, previous.id)
        XCTAssertEqual(actual?.heartRateChange, -8)
        XCTAssertEqual(actual?.powerChange, -16)
        XCTAssertEqual(actual?.speedChange ?? 0, 0.2, accuracy: 0.0001)
    }

    func testNeverComparesRunsWithoutAllThreeMeasurements() {
        let latest = run(daysAgo: 0)
        XCTAssertNil(ATHLTHInsightsRunComparisonPolicy.closestComparable(
            to: latest,
            among: [
                run(daysAgo: 4, power: nil),
                run(daysAgo: 7, heart: nil),
                run(daysAgo: 12, speed: nil)
            ]
        ))
        XCTAssertNil(ATHLTHInsightsRunComparisonPolicy.closestComparable(
            to: run(daysAgo: 0, heart: nil),
            among: [run(daysAgo: 12)]
        ))
    }

    func testDoesNotMislabelDerivedSpeedAsDirectlyMeasured() {
        let latest = run(daysAgo: 0, calculatedSpeed: false)
        let olderDerived = run(daysAgo: 8, calculatedSpeed: true)
        XCTAssertNil(ATHLTHInsightsRunComparisonPolicy.closestComparable(
            to: latest, among: [olderDerived]
        ))
    }

    func testRejectsMismatchedSpeedDurationAndFutureComparisons() {
        let latest = run(daysAgo: 3)
        let tooFast = run(daysAgo: 7, speed: 13.4)
        let tooLong = run(daysAgo: 8, minutes: 60)
        let future = run(daysAgo: 0)
        XCTAssertNil(ATHLTHInsightsRunComparisonPolicy.closestComparable(
            to: latest,
            among: [tooFast, tooLong, future]
        ))
    }

    func testFindsNearestMatchingEffortNotMostFlatteringHeartRate() {
        let latest = run(daysAgo: 0, heart: 150, power: 265, speed: 11.0)
        let closest = run(
            daysAgo: 28, minutes: 41, heart: 162, power: 300, speed: 11.1
        )
        let betterLooking = run(
            daysAgo: 8, minutes: 48, heart: 140, power: 250, speed: 11.5
        )
        XCTAssertEqual(
            ATHLTHInsightsRunComparisonPolicy.closestComparable(
                to: latest, among: [betterLooking, closest]
            )?.previous.id,
            closest.id
        )
    }

    func testEmptyOrTooShortWorkoutNeverGetsFalseComparison() {
        let short = run(daysAgo: 0, minutes: 8)
        XCTAssertNil(ATHLTHInsightsRunComparisonPolicy.closestComparable(
            to: short,
            among: [run(daysAgo: 3, minutes: 8)]
        ))
    }
}
