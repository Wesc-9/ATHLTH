import XCTest
@testable import ATHLTH

final class ATHLTHLiveCoachWorkoutStatusTests: XCTestCase {
    func testStaleMirroredMetricsNeverReachAI() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var snapshot = WatchWorkoutLiveSnapshot(
            kind: .running, state: .running,
            startedAt: now.addingTimeInterval(-100),
            capturedAt: now.addingTimeInterval(-20),
            elapsedTime: 100, heartRate: 140,
            activeCalories: 50, distanceMeters: 500,
            averageHeartRate: nil, maxHeartRate: nil,
            routePointCount: 1
        )
        snapshot.coachHeartRateSampleAt = now
        snapshot.currentPaceSecondsPerKilometer = 310
        snapshot.coachPaceSampleAt = now
        let status = ATHLTHLiveCoachWorkoutStatus.fromWatch(snapshot, now: now)
        XCTAssertEqual(status.availability, "unavailable")
        XCTAssertNil(status.paceSecondsPerKilometer)
        XCTAssertNil(status.heartRateBPM)
    }

    func testFreshWatchSamplesRequireFreshSensorTimestamps() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var snapshot = WatchWorkoutLiveSnapshot(
            kind: .running, state: .running,
            startedAt: now.addingTimeInterval(-100),
            capturedAt: now, elapsedTime: 100, heartRate: 145,
            activeCalories: 50, distanceMeters: 500,
            averageHeartRate: nil, maxHeartRate: nil, routePointCount: 1
        )
        snapshot.currentPaceSecondsPerKilometer = 310
        var status = ATHLTHLiveCoachWorkoutStatus.fromWatch(snapshot, now: now)
        XCTAssertEqual(status.availability, "available")
        XCTAssertNil(status.paceSecondsPerKilometer)
        XCTAssertNil(status.heartRateBPM)
        snapshot.coachHeartRateSampleAt = now
        snapshot.coachPaceSampleAt = now
        status = ATHLTHLiveCoachWorkoutStatus.fromWatch(snapshot, now: now)
        XCTAssertEqual(status.paceSecondsPerKilometer, 310)
        XCTAssertEqual(status.heartRateBPM, 145)
        XCTAssertFalse(status.json.contains("longitude"))
        XCTAssertFalse(status.json.contains("latitude"))
        snapshot.state = .paused
        status = ATHLTHLiveCoachWorkoutStatus.fromWatch(snapshot, now: now)
        XCTAssertNil(status.paceSecondsPerKilometer)
    }
}
