import CoreLocation
import XCTest
@testable import ATHLTH

final class ATHLTHRouteDirectionGeometryTests: XCTestCase {
    func testRetracedRoadHasTurnaroundAndTwoOpposingLegArrows() throws {
        // Exactly the same road travelled outbound then inbound.
        let latitudes: [Double] = [
            63.4300, 63.4305, 63.4310, 63.4315, 63.4320, 63.4325,
            63.4320, 63.4315, 63.4310, 63.4305, 63.4300
        ]
        let route = latitudes.map {
            CLLocationCoordinate2D(latitude: $0, longitude: 10.4)
        }
        let turn = try XCTUnwrap(
            ATHLTHRouteDirectionGeometry.turnaroundIndex(route)
        )
        XCTAssertEqual(turn, 5)
        let arrows = ATHLTHRouteDirectionGeometry.arrows(for: route)
        XCTAssertEqual(arrows.count, 2)
        XCTAssertFalse(arrows[0].returning)
        XCTAssertTrue(arrows[1].returning)
        XCTAssertLessThan(abs(arrows[0].bearingDegrees), 15)
        XCTAssertGreaterThan(abs(arrows[1].bearingDegrees), 160)
    }

    func testClosedLoopDoesNotInventOutAndBackTurnaround() {
        let route = [
            CLLocationCoordinate2D(latitude: 63.4300, longitude: 10.4000),
            CLLocationCoordinate2D(latitude: 63.4300, longitude: 10.4025),
            CLLocationCoordinate2D(latitude: 63.4325, longitude: 10.4025),
            CLLocationCoordinate2D(latitude: 63.4350, longitude: 10.4025),
            CLLocationCoordinate2D(latitude: 63.4350, longitude: 10.4000),
            CLLocationCoordinate2D(latitude: 63.4350, longitude: 10.3975),
            CLLocationCoordinate2D(latitude: 63.4325, longitude: 10.3975),
            CLLocationCoordinate2D(latitude: 63.4300, longitude: 10.3975),
            CLLocationCoordinate2D(latitude: 63.4300, longitude: 10.4000)
        ]
        XCTAssertNil(ATHLTHRouteDirectionGeometry.turnaroundIndex(route))
        let arrows = ATHLTHRouteDirectionGeometry.arrows(for: route)
        XCTAssertTrue(arrows.allSatisfy { !$0.returning })
    }

    func testTooShortRouteDoesNotShowMisleadingDirectionMarkers() {
        let route = [
            CLLocationCoordinate2D(latitude: 63.43, longitude: 10.40),
            CLLocationCoordinate2D(latitude: 63.4301, longitude: 10.40)
        ]
        XCTAssertNil(ATHLTHRouteDirectionGeometry.turnaroundIndex(route))
        XCTAssertTrue(ATHLTHRouteDirectionGeometry.arrows(for: route).isEmpty)
    }
}
