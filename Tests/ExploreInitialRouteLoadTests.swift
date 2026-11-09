import CoreLocation
import XCTest
@testable import ATHLTH

final class ExploreInitialRouteLoadTests: XCTestCase {
    func testNearbyLookupBoundsCoverTrondheimAndRejectDistantRoutes() throws {
        let center = CLLocationCoordinate2D(
            latitude: 63.4305,
            longitude: 10.3951
        )
        let bounds = try XCTUnwrap(RouteDiscoveryNearbyBounds(
            coordinate: center,
            radiusKilometers: 50
        ))
        XCTAssertLessThan(bounds.minLatitude, center.latitude)
        XCTAssertGreaterThan(bounds.maxLatitude, center.latitude)

        let west = try XCTUnwrap(bounds.minLongitude)
        let east = try XCTUnwrap(bounds.maxLongitude)
        XCTAssertLessThan(west, center.longitude)
        XCTAssertGreaterThan(east, center.longitude)

        // Oslo is far away: its routes should not consume the local map page.
        XCTAssertGreaterThan(bounds.minLatitude, 59.9139)
        XCTAssertLessThan(bounds.maxLatitude, 64.0)
    }

    func testDatelineLookupSafelySkipsLongitudePrefilter() throws {
        let bounds = try XCTUnwrap(RouteDiscoveryNearbyBounds(
            coordinate: CLLocationCoordinate2D(
                latitude: 65.0,
                longitude: 179.9
            ),
            radiusKilometers: 50
        ))
        XCTAssertNil(bounds.minLongitude)
        XCTAssertNil(bounds.maxLongitude)
    }

    func testInvalidLocationDoesNotMakeARequest() {
        XCTAssertNil(RouteDiscoveryNearbyBounds(
            coordinate: CLLocationCoordinate2D(
                latitude: 100,
                longitude: 10
            ),
            radiusKilometers: 50
        ))
        XCTAssertNil(RouteDiscoveryNearbyBounds(
            coordinate: CLLocationCoordinate2D(
                latitude: 63.4,
                longitude: 10.4
            ),
            radiusKilometers: 0
        ))
    }
}
