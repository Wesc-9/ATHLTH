import Foundation
import XCTest
@testable import ATHLTH

final class GlobalSearchRoutePresentationTests: XCTestCase {
    func testShortFlatRouteHasUsefulWalkAndRunEstimates() {
        XCTAssertEqual(
            ATHLTHSearchRoutePresentation.estimatedMinutes(
                distanceKilometers: 2.6,
                ascentMeters: nil,
                walking: true
            ),
            31
        )
        XCTAssertEqual(
            ATHLTHSearchRoutePresentation.estimatedMinutes(
                distanceKilometers: 2.6,
                ascentMeters: nil,
                walking: false
            ),
            17
        )
    }

    func testElevationAddsTimeWithoutInventingRecordedActivity() {
        let walk = ATHLTHSearchRoutePresentation.estimatedMinutes(
            distanceKilometers: 2.6,
            ascentMeters: 100,
            walking: true
        )
        let run = ATHLTHSearchRoutePresentation.estimatedMinutes(
            distanceKilometers: 2.6,
            ascentMeters: 100,
            walking: false
        )
        XCTAssertEqual(walk, 37)
        XCTAssertEqual(run, 21)
    }

    func testInvalidRouteDistancesDoNotProduceEstimatedTimes() {
        for distance in [-1.0, 0.0, .nan, .infinity] {
            XCTAssertNil(ATHLTHSearchRoutePresentation.estimatedMinutes(
                distanceKilometers: distance,
                ascentMeters: 0,
                walking: true
            ))
        }
    }

    func testTravelDurationAndDistanceLocalization() {
        XCTAssertEqual(
            ATHLTHSearchRoutePresentation.localizedDuration(67, norwegian: true),
            "1 t 7 min"
        )
        XCTAssertEqual(
            ATHLTHSearchRoutePresentation.localizedDuration(120, norwegian: true),
            "2 t"
        )
        XCTAssertEqual(
            ATHLTHSearchRoutePresentation.localizedDuration(67, norwegian: false),
            "1 h 7 min"
        )
        XCTAssertEqual(
            ATHLTHSearchRoutePresentation.distance(2.6, norwegian: true),
            "2,6 km"
        )
        XCTAssertEqual(
            ATHLTHSearchRoutePresentation.distance(2.6, norwegian: false),
            "2.6 km"
        )
    }
}
