import CoreLocation
import XCTest
@testable import ATHLTH

final class HomeActivityCenterSafetyTests: XCTestCase {
    func testInvalidCoordinatesAreRemovedBeforeMapKit() {
        let locations = [
            CLLocation(
                latitude: 63.4305,
                longitude: 10.3951
            ),
            CLLocation(
                latitude: .nan,
                longitude: 10.40
            ),
            CLLocation(
                latitude: 63.44,
                longitude: .infinity
            ),
            CLLocation(
                latitude: 91,
                longitude: 10
            ),
            CLLocation(
                latitude: 63.45,
                longitude: 10.41
            )
        ]

        let valid =
            HomeActivityRouteSanitizer
                .validLocations(locations)

        XCTAssertEqual(valid.count, 2)
        XCTAssertTrue(
            valid.allSatisfy {
                CLLocationCoordinate2DIsValid(
                    $0.coordinate
                )
            }
        )
    }

    func testRouteSamplingIsBoundedAndKeepsEndpoints() {
        let coordinates =
            (0..<250).map {
                index in

                CLLocationCoordinate2D(
                    latitude:
                        63.40 +
                        Double(index) * 0.0001,
                    longitude:
                        10.30 +
                        Double(index) * 0.0001
                )
            }

        let sampled =
            HomeActivityRouteSanitizer.sampled(
                coordinates,
                maximumCount: 96
            )

        XCTAssertEqual(sampled.count, 96)
        XCTAssertEqual(
            sampled.first?.latitude,
            coordinates.first?.latitude
        )
        XCTAssertEqual(
            sampled.last?.latitude,
            coordinates.last?.latitude
        )
    }
}
