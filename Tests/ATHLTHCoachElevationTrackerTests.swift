import Foundation
import CoreLocation
import XCTest
@testable import ATHLTH

final class ATHLTHCoachElevationTrackerTests: XCTestCase {
    private func fix(
        latitude: Double, altitude: Double, at date: Date,
        verticalAccuracy: Double = 4
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: latitude, longitude: 10.4
            ),
            altitude: altitude,
            horizontalAccuracy: 5,
            verticalAccuracy: verticalAccuracy,
            timestamp: date
        )
    }

    func testAscentRequiresTwoReliableOutdoorLocations() {
        let now = Date()
        var tracker = ATHLTHCoachElevationTracker()
        tracker.observe(fix(latitude: 63.42, altitude: 25, at: now), now: now)
        XCTAssertFalse(tracker.hasReliableGain)
        XCTAssertEqual(tracker.gainMeters, 0)
        tracker.observe(fix(latitude: 63.4202, altitude: 33,
                            at: now.addingTimeInterval(8)),
                        now: now.addingTimeInterval(8))
        XCTAssertTrue(tracker.hasReliableGain)
        XCTAssertEqual(tracker.gainMeters, 8, accuracy: 0.01)
        XCTAssertEqual(tracker.uphill, true)
        tracker.observe(fix(latitude: 63.4204, altitude: 31,
                            at: now.addingTimeInterval(16)),
                        now: now.addingTimeInterval(16))
        XCTAssertEqual(tracker.gainMeters, 8, accuracy: 0.01)
        XCTAssertEqual(tracker.uphill, false)
    }

    func testVerticalNoiseDoesNotFabricateElevation() {
        let now = Date()
        var tracker = ATHLTHCoachElevationTracker()
        tracker.observe(fix(latitude: 63.42, altitude: 30, at: now), now: now)
        tracker.observe(fix(latitude: 63.4202, altitude: 40,
                            at: now.addingTimeInterval(8),
                            verticalAccuracy: 25),
                        now: now.addingTimeInterval(8))
        XCTAssertEqual(tracker.gainMeters, 0)
        XCTAssertNil(tracker.uphill)
    }

    func testResetClearsPreviousWorkoutElevation() {
        let now = Date()
        var tracker = ATHLTHCoachElevationTracker()
        tracker.observe(fix(latitude: 63.42, altitude: 30, at: now), now: now)
        tracker.observe(fix(latitude: 63.4202, altitude: 38,
                            at: now.addingTimeInterval(8)),
                        now: now.addingTimeInterval(8))
        tracker.reset()
        XCTAssertEqual(tracker.gainMeters, 0)
        XCTAssertFalse(tracker.hasReliableGain)
        XCTAssertNil(tracker.uphill)
    }
}
