import CoreLocation
import XCTest
@testable import ATHLTH

final class WorkoutRouteSharingTests: XCTestCase {
    func testShortRouteNeverFallsBackToOriginal() {
        let route = (0..<10).map { point(Double($0) * 0.0001) }
        XCTAssertTrue(WorkoutRouteSharing.preview(route, hideStartAndEnd: true).isEmpty)
        XCTAssertEqual(WorkoutRouteSharing.preview(route, hideStartAndEnd: false).count, 10)
    }

    func testProtectedPreviewExcludesBothEndpointAreas() throws {
        let route = (0..<100).map { point(Double($0) * 0.0001) }
        let result = WorkoutRouteSharing.preview(route, hideStartAndEnd: true)
        XCTAssertFalse(result.isEmpty)
        for coordinate in result {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            XCTAssertGreaterThanOrEqual(location.distance(from: route.first!), 250)
            XCTAssertGreaterThanOrEqual(location.distance(from: route.last!), 250)
            XCTAssertNil(coordinate.altitude)
        }
        let encoded = try XCTUnwrap(WorkoutRouteSharing.encode(result))
        XCTAssertEqual(WorkoutRouteSharing.decode(encoded), result)
    }

    func testSparseRouteCannotDrawAcrossHiddenStart() {
        let route = [point(0), point(0.01), point(-0.01), point(-0.02)]
        let result = WorkoutRouteSharing.preview(route, hideStartAndEnd: true)
        XCTAssertTrue(result.isEmpty)
    }

    func testInvalidLocationsAndUntrustedPayloadsAreRejected() {
        XCTAssertTrue(WorkoutRouteSharing.preview([point(0), point(100)], hideStartAndEnd: false).isEmpty)
        XCTAssertTrue(WorkoutRouteSharing.decode("not JSON").isEmpty)
        XCTAssertTrue(WorkoutRouteSharing.decode(String(repeating: " ", count: 50_001)).isEmpty)
        XCTAssertTrue(WorkoutRouteSharing.decode(nil).isEmpty)
    }

    func testLargeRouteProducesBoundedPreview() {
        let route = (0..<10_000).map { point(Double($0) * 0.00001) }
        let result = WorkoutRouteSharing.preview(route, hideStartAndEnd: true)
        XCTAssertGreaterThanOrEqual(result.count, 2)
        XCTAssertLessThanOrEqual(result.count, 300)
    }

    private func point(_ latitude: Double) -> CLLocation {
        CLLocation(latitude: latitude, longitude: 10)
    }
}
