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
