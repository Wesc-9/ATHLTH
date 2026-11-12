import XCTest
@testable import ATHLTH

final class ATHLTHWidgetPresentationPolicyTests: XCTestCase {
    func testFourByFourShowsActualEffortIntervals() {
        XCTAssertEqual(
            ATHLTHWidgetPresentationPolicy.intervalLabel(
                ordinal: 1, total: 4, isRecovery: false
            ), "1 av 4"
        )
        XCTAssertEqual(
            ATHLTHWidgetPresentationPolicy.intervalLabel(
                ordinal: 1, total: 4, isRecovery: true
            ), "Neste 2 av 4"
        )
        XCTAssertEqual(
            ATHLTHWidgetPresentationPolicy.intervalLabel(
                ordinal: 4, total: 4, isRecovery: true
            ), "Neste 4 av 4"
        )
    }

    func testFreeRunDoesNotInventIntervalCounter() {
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.intervalLabel(
            ordinal: nil, total: nil, isRecovery: false
        ))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.intervalLabel(
            ordinal: 1, total: 1, isRecovery: false
        ))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.intervalLabel(
            ordinal: 5, total: 4, isRecovery: false
        ))
    }

    func testCountdownRejectsInvalidSensorValues() {
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.remainingSeconds(.nan))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.remainingSeconds(.infinity))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.remainingSeconds(-3))
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.remainingSeconds(0), 0)
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.remainingSeconds(32), 32)
    }

    func testLongDurationIsNotTruncatedToMinutes() {
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.duration(90), "01:30")
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.duration(3_661), "1:01:01")
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.duration(0.2), "00:01")
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.duration(.nan), "00:00")
    }

    func testBadHeartRateAndDistanceAreNotDisplayed() {
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.heartRateLabel(.nan))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.heartRateLabel(0))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.distanceLabel(.infinity))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.distanceLabel(-12))
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.heartRateLabel(148), "148 bpm")
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.distanceLabel(5_250), "5.25 km")
    }
}
