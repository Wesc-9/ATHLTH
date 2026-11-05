import CoreLocation
import XCTest
@testable import ATHLTH

final class ATHLTHContinuousRouteGuidanceTests: XCTestCase {
    private let start = CLLocation(latitude: 63.4305, longitude: 10.3900)
    private let end = CLLocation(latitude: 63.4305, longitude: 10.3970)

    private func guidance(at location: CLLocation) -> ATHLTHRouteGuidanceState? {
        let route = [start, end]
        let geometry = ATHLTHRouteGuidanceEngine.cumulativeGeometry(
            locations: route
        )
        return ATHLTHRouteGuidanceEngine.state(
            location: location,
            routeLocations: route,
            cumulativeMeters: geometry.cumulativeMeters,
            geometryTotalMeters: geometry.totalMeters,
            advertisedDistanceMeters: geometry.totalMeters,
            workoutDistanceMeters: geometry.totalMeters / 2
        )
    }

    func testMidpointOfSparseStraightIsStillOnTheRoute() throws {
        // The nearest GPX vertex is roughly 175 m away here. Distance
        // to the actual continuous path is approximately zero.
        let midway = CLLocation(latitude: 63.4305, longitude: 10.3935)
        let state = try XCTUnwrap(guidance(at: midway))
        XCTAssertLessThan(state.deviationMeters, 8)
        XCTAssertEqual(state.progressPercent, 50, accuracy: 4)
    }

    func testGenuinePerpendicularDeviationIsNotHidden() throws {
        let offPath = CLLocation(latitude: 63.4313, longitude: 10.3935)
        let state = try XCTUnwrap(guidance(at: offPath))
        XCTAssertGreaterThan(state.deviationMeters, 70)
        XCTAssertLessThan(state.deviationMeters, 110)
    }

    func testRouteProgressRemainsBoundedAtEndpoints() throws {
        let atStart = try XCTUnwrap(guidance(at: start))
        XCTAssertGreaterThanOrEqual(atStart.progressPercent, 0)
        let atFinish = try XCTUnwrap(guidance(at: end))
        XCTAssertLessThanOrEqual(atFinish.progressPercent, 100)
    }
}
