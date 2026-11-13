import XCTest
@testable import ATHLTH

final class ATHLTHHeartRateZonesMeasuredTests: XCTestCase {
    func testObservedZonesFollowExistingFiveZoneScale() {
        // 50–60–70–80–90% of configured max HR; no training targets involved.
        XCTAssertEqual(ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: 110, maximumBPM: 200
        ), 1)
        XCTAssertEqual(ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: 130, maximumBPM: 200
        ), 2)
        XCTAssertEqual(ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: 150, maximumBPM: 200
        ), 3)
        XCTAssertEqual(ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: 170, maximumBPM: 200
        ), 4)
        XCTAssertEqual(ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: 190, maximumBPM: 200
        ), 5)
    }

    func testFiveZoneRangesUseSelectedAthletesMaximum() {
        XCTAssertEqual(
            ATHLTHHeartRateZones.range(for: 1, maximumBPM: 190),
            95...114
        )
        XCTAssertEqual(
            ATHLTHHeartRateZones.range(for: 5, maximumBPM: 190),
            171...190
        )
        XCTAssertEqual(
            ATHLTHHeartRateZones.range(from: 1, through: 2, maximumBPM: 190),
            95...133
        )
        XCTAssertEqual(
            ATHLTHHeartRateZones.range(
                fromPercent: 90, toPercent: 100, maximumBPM: 190
            ),
            171...190
        )
        XCTAssertEqual(
            ATHLTHHeartRateZones.matchingZones(
                for: 95...133, maximumBPM: 190
            ),
            Set([1, 2])
        )
    }

    func testDifferentHRMaxSourcesChangeZonesWithoutChangingMeasuredPulse() {
        XCTAssertEqual(
            ATHLTHHeartRateZones.measuredZone(
                heartRateBPM: 125, maximumBPM: 190
            ),
            2
        )
        XCTAssertEqual(
            ATHLTHHeartRateZones.measuredZone(
                heartRateBPM: 125, maximumBPM: 220
            ),
            1
        )
        XCTAssertNil(
            ATHLTHHeartRateZones.range(from: 2, through: 1, maximumBPM: 190)
        )
        XCTAssertNil(
            ATHLTHHeartRateZones.range(from: 1, through: 2, maximumBPM: nil)
        )
    }

    func testSexSpecificAgeFallbackOnlyUsedWithoutConfiguredHRMax() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let birth = calendar.date(from: DateComponents(
            year: 1990, month: 6, day: 13
        ))!
        let date = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 14
        ))!
        XCTAssertEqual(
            ATHLTHHeartRateZones.resolvedMaximumBPM(
                configured: 193, dateOfBirth: birth, now: date,
                usesFemaleEstimate: true
            ),
            193
        )
        let female = try XCTUnwrap(
            ATHLTHHeartRateZones.resolvedMaximumBPM(
                configured: nil, dateOfBirth: birth, now: date,
                usesFemaleEstimate: true
            )
        )
        XCTAssertEqual(female, 206 - 0.88 * 36, accuracy: 0.0001)
    }

    func testUnavailableOrInvalidPulseCannotAppearAsAMeasuredZone() {
        XCTAssertNil(ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: nil, maximumBPM: 200
        ))
        XCTAssertNil(ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: 109, maximumBPM: nil
        ))
        XCTAssertNil(ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: 0, maximumBPM: 200
        ))
        XCTAssertNil(ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: .nan, maximumBPM: 200
        ))
        XCTAssertNil(ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: 110, maximumBPM: .infinity
        ))
        XCTAssertNil(ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: 95, maximumBPM: 200
        ))
    }
}
