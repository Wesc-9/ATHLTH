import CoreLocation
import XCTest
@testable import ATHLTH

final class ATHLTHStationaryTimeEstimatorTests: XCTestCase {
    private func point(
        seconds: TimeInterval,
        latitude: Double = 67.258,
        longitude: Double = 15.393,
        speed: CLLocationSpeed = -1,
        accuracy: CLLocationAccuracy = 5
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            course: -1,
            speed: speed,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + seconds)
        )
    }

    func testTwentySecondsStandingStillIsCounted() {
        let locations = [
            point(seconds: 0, longitude: 15.390),
            point(seconds: 5, longitude: 15.3902),
            point(seconds: 10, longitude: 15.3904),
            point(seconds: 15, longitude: 15.3906),
            point(seconds: 20, longitude: 15.3906, speed: 0),
            point(seconds: 25, longitude: 15.3906, speed: 0),
            point(seconds: 30, longitude: 15.3906, speed: 0),
            point(seconds: 35, longitude: 15.3906, speed: 0),
            point(seconds: 40, longitude: 15.3906, speed: 0),
            point(seconds: 45, longitude: 15.3908),
            point(seconds: 50, longitude: 15.391)
        ]
        let total = ATHLTHStationaryTimeEstimator.waitingSeconds(
            from: locations, workoutDuration: 50
        )
        XCTAssertEqual(total, 25)
    }

    func testSparseRouteDoesNotInventPauses() {
        let locations = [
            point(seconds: 0), point(seconds: 60),
            point(seconds: 120), point(seconds: 180)
        ]
        XCTAssertNil(ATHLTHStationaryTimeEstimator.waitingSeconds(
            from: locations, workoutDuration: 180
        ))
    }

    func testMovingRouteHasZeroWaiting() {
        let locations = (0...10).map { i in
            point(seconds: Double(i * 5),
                  longitude: 15.390 + Double(i) * 0.00025,
                  speed: 2.0)
        }
        XCTAssertEqual(ATHLTHStationaryTimeEstimator.waitingSeconds(
            from: locations, workoutDuration: 50
        ), 0)
    }

    func testUnreliableAccuracyDoesNotCountAsWaiting() {
        let locations = (0...10).map { i in
            point(seconds: Double(i * 5), accuracy: 50)
        }
        XCTAssertNil(ATHLTHStationaryTimeEstimator.waitingSeconds(
            from: locations, workoutDuration: 50
        ))
    }

    func testShortJitterIsNotWaiting() {
        let locations = [
            point(seconds: 0, longitude: 15.3900),
            point(seconds: 5, longitude: 15.3903),
            point(seconds: 10, longitude: 15.3903),
            point(seconds: 15, longitude: 15.3903),
            point(seconds: 20, longitude: 15.3906),
            point(seconds: 25, longitude: 15.3909),
            point(seconds: 30, longitude: 15.3912),
            point(seconds: 35, longitude: 15.3915)
        ]
        XCTAssertEqual(ATHLTHStationaryTimeEstimator.waitingSeconds(
            from: locations, workoutDuration: 35
        ), 0)
    }
}
