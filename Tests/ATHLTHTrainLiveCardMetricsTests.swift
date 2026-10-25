import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainLiveCardMetricsTests: XCTestCase {
    func testUnknownDistanceOrNonFiniteReadingIsNotDisplayed() {
        XCTAssertNil(ATHLTHTrainLiveCardMetrics.distanceLabel(
            meters: 0, estimated: false
        ))
        XCTAssertNil(ATHLTHTrainLiveCardMetrics.distanceLabel(
            meters: .infinity, estimated: true
        ))
        XCTAssertNil(ATHLTHTrainLiveCardMetrics.averagePaceLabel(
            activeSeconds: 20, meters: 0
        ))
    }

    func testTreadmillDistanceAlwaysCarriesEstimateLabel() {
        let value = ATHLTHTrainLiveCardMetrics.distanceLabel(
            meters: 3250, estimated: true
        )
        XCTAssertTrue(value?.contains("estimert") == true)
        XCTAssertFalse(value?.contains("GPS") == true)
    }

    func testMeasuredOutdoorDistanceUsesGPSSource() {
        let value = ATHLTHTrainLiveCardMetrics.distanceLabel(
            meters: 5000, estimated: false
        )
        XCTAssertTrue(value?.contains("GPS") == true)
        XCTAssertFalse(value?.contains("estimert") == true)
    }

    func testAveragePaceUsesActiveSecondsAndHasReliableBounds() {
        XCTAssertEqual(
            ATHLTHTrainLiveCardMetrics.averagePaceLabel(
                activeSeconds: 1500, meters: 5000
            ),
            "Snitt 5:00/km"
        )
        XCTAssertNil(ATHLTHTrainLiveCardMetrics.averagePaceLabel(
            activeSeconds: 12, meters: 12
        ))
        XCTAssertNil(ATHLTHTrainLiveCardMetrics.averagePaceLabel(
            activeSeconds: .infinity, meters: 5000
        ))
    }
}
