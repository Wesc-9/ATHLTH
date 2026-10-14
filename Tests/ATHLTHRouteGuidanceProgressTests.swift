import CoreLocation
import XCTest
@testable import ATHLTH

/// A round route can have its finish only a few metres from its start.
/// Never advance the runner to the end simply because GPS sees the finish.
final class ATHLTHRouteGuidanceProgressTests: XCTestCase {
    private let originLatitude = 63.43
    private let originLongitude = 10.40

    private func location(east: Double, north: Double) -> CLLocation {
        let latitude = originLatitude + north / 111_132
        let longitude = originLongitude +
            east / (111_320 * cos(originLatitude * .pi / 180))
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    private func route() -> [CLLocation] {
        [
            location(east: 0, north: 0),        // start
            location(east: 0, north: 100),
            location(east: 100, north: 100),
            location(east: 100, north: 0),
            location(east: 2, north: 0)         // finish near start
        ]
    }

    private func match(
        _ position: CLLocation,
        workoutDistance: Double,
        previousMeters: Double? = nil
    ) throws -> ATHLTHRouteGuidanceState {
        let points = route()
        let geometry = ATHLTHRouteGuidanceEngine.cumulativeGeometry(
            locations: points
        )
        return try XCTUnwrap(ATHLTHRouteGuidanceEngine.state(
            location: position,
            routeLocations: points,
            cumulativeMeters: geometry.cumulativeMeters,
            geometryTotalMeters: geometry.totalMeters,
            advertisedDistanceMeters: geometry.totalMeters,
            workoutDistanceMeters: workoutDistance,
            previousRouteMeters: previousMeters
        ))
    }

    func testAtStartNeverSnapsToNearbyFinish() throws {
        let position = location(east: 1.9, north: 0)
        let result = try match(position, workoutDistance: 0)
        XCTAssertEqual(result.nearestRoutePointIndex, 0)
        XCTAssertEqual(result.progressPercent, 0, accuracy: 0.001)
        XCTAssertGreaterThan(result.remainingMeters, 350)
    }

    func testFirstMetersStillCannotClaimFinish() throws {
        let position = location(east: 2, north: 0)
        let result = try match(position, workoutDistance: 25)
        XCTAssertEqual(result.nearestRoutePointIndex, 0)
        XCTAssertLessThan(result.progressPercent, 5)
    }

    func testIntermediateProgressUsesCorrectRouteSection() throws {
        let result = try match(
            location(east: 100, north: 100),
            workoutDistance: 200,
            previousMeters: 105
        )
        XCTAssertEqual(result.nearestRoutePointIndex, 2)
        XCTAssertEqual(result.progressPercent, 50, accuracy: 3)
    }

    func testFinishBecomesAvailableOnlyAfterTravelingRoute() throws {
        let points = route()
        let geometry = ATHLTHRouteGuidanceEngine.cumulativeGeometry(
            locations: points
        )
        let result = try match(
            points.last!,
            workoutDistance: geometry.totalMeters - 8,
            previousMeters: geometry.totalMeters - 95
        )
        XCTAssertEqual(result.nearestRoutePointIndex, 4)
        XCTAssertEqual(result.progressPercent, 100, accuracy: 0.001)
    }

    func testPreviousProgressPreventsJumpBackToStartAtCrossing() throws {
        let result = try match(
            location(east: 0, north: 0),
            workoutDistance: 230,
            previousMeters: 200
        )
        XCTAssertNotEqual(result.nearestRoutePointIndex, 0)
    }

    func testNoWorkoutDistanceKeepsLegacyClosestPointBehavior() throws {
        let points = route()
        let geometry = ATHLTHRouteGuidanceEngine.cumulativeGeometry(
            locations: points
        )
        let result = try XCTUnwrap(ATHLTHRouteGuidanceEngine.state(
            location: points.last!,
            routeLocations: points,
            cumulativeMeters: geometry.cumulativeMeters,
            geometryTotalMeters: geometry.totalMeters,
            advertisedDistanceMeters: nil
        ))
        XCTAssertEqual(result.nearestRoutePointIndex, 4)
    }
}
