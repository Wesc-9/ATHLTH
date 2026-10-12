import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutAccessibleMetricTests: XCTestCase {
    func testDurationUsesSpokenUnitsNotClockPunctuation() {
        XCTAssertEqual(
            ATHLTHWorkoutAccessibleMetric.duration(3_661, norwegian: true),
            "1 time, 1 minutt, 1 sekund"
        )
        XCTAssertEqual(
            ATHLTHWorkoutAccessibleMetric.duration(125, norwegian: false),
            "2 minutes, 5 seconds"
        )
        XCTAssertEqual(
            ATHLTHWorkoutAccessibleMetric.duration(0, norwegian: true),
            "0 sekunder"
        )
    }

    func testInvalidOrMissingDataIsNotAnnouncedAsZero() {
        XCTAssertEqual(
            ATHLTHWorkoutAccessibleMetric.duration(.nan, norwegian: true),
            "Tid ikke tilgjengelig"
        )
        XCTAssertEqual(
            ATHLTHWorkoutAccessibleMetric.distance(.infinity, norwegian: false),
            "Distance unavailable"
        )
        XCTAssertEqual(
            ATHLTHWorkoutAccessibleMetric.pulse(
                140, isFresh: false, norwegian: true
            ),
            "Venter på pulsmåling"
        )
    }

    func testPulseAndDistanceNarrateRealUnits() {
        XCTAssertEqual(
            ATHLTHWorkoutAccessibleMetric.pulse(
                146.4, isFresh: true, norwegian: true
            ),
            "146 slag i minuttet"
        )
        XCTAssertEqual(
            ATHLTHWorkoutAccessibleMetric.distance(640, norwegian: true),
            "640 meter"
        )
        XCTAssertEqual(
            ATHLTHWorkoutAccessibleMetric.distance(2_500, norwegian: false),
            "2.50 kilometers"
        )
    }
}
