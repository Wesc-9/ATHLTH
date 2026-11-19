import XCTest
@testable import ATHLTH

final class ATHLTHWidgetPresentationPolicyTests: XCTestCase {
    private func surfaceWorkout(
        startedAt: Date,
        capturedAt: Date,
        title: String = "Run",
        state: String = "running",
        systemImage: String = "figure.run"
    ) -> ATHLTHSurfaceWorkoutSnapshot {
        ATHLTHSurfaceWorkoutSnapshot(
            title: title, systemImage: systemImage,
            state: state, startedAt: startedAt,
            elapsedTime: 120, distanceMeters: 500,
            heartRate: 140, updatedAt: capturedAt
        )
    }

    func testWidgetRejectsDelayedWatchStatusAndAcceptsNewerIntervalState() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let old = surfaceWorkout(
            startedAt: start, capturedAt: start.addingTimeInterval(15)
        )
        let latest = surfaceWorkout(
            startedAt: start, capturedAt: start.addingTimeInterval(30)
        )
        let now = start.addingTimeInterval(35)
        XCTAssertFalse(ATHLTHSurfaceWorkoutOrdering.accepts(
            incoming: old, current: latest, terminal: nil, now: now
        ))
        XCTAssertTrue(ATHLTHSurfaceWorkoutOrdering.accepts(
            incoming: latest, current: old, terminal: nil, now: now
        ))
    }

    func testWidgetTerminalWatermarkCannotReopenOldWorkout() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let workout = surfaceWorkout(
            startedAt: start, capturedAt: start.addingTimeInterval(80)
        )
        let ended = ATHLTHSurfaceWorkoutTerminalMarker(
            workout: workout, finishedAt: start.addingTimeInterval(90)
        )
        XCTAssertFalse(ATHLTHSurfaceWorkoutOrdering.accepts(
            incoming: workout, current: nil,
            terminal: ended, now: start.addingTimeInterval(95)
        ))
        var renamed = workout
        renamed.title = "Evening intervals"
        XCTAssertFalse(ATHLTHSurfaceWorkoutOrdering.accepts(
            incoming: renamed, current: nil,
            terminal: ended, now: start.addingTimeInterval(95)
        ))
        let next = surfaceWorkout(
            startedAt: start.addingTimeInterval(150),
            capturedAt: start.addingTimeInterval(155)
        )
        XCTAssertTrue(ATHLTHSurfaceWorkoutOrdering.accepts(
            incoming: next, current: nil,
            terminal: ended, now: start.addingTimeInterval(160)
        ))
    }

    func testOlderWorkoutCannotReplaceNewerWidgetAfterDeviceSwitch() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let old = surfaceWorkout(
            startedAt: start, capturedAt: start.addingTimeInterval(60)
        )
        let newPhone = surfaceWorkout(
            startedAt: start.addingTimeInterval(120),
            capturedAt: start.addingTimeInterval(140)
        )
        XCTAssertFalse(ATHLTHSurfaceWorkoutOrdering.accepts(
            incoming: old, current: newPhone,
            terminal: nil, now: start.addingTimeInterval(145)
        ))
        XCTAssertTrue(ATHLTHSurfaceWorkoutOrdering.accepts(
            incoming: newPhone, current: old,
            terminal: nil, now: start.addingTimeInterval(145)
        ))
    }

    func testInvalidFutureWidgetCaptureIsRejected() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let now = start.addingTimeInterval(100)
        XCTAssertFalse(ATHLTHSurfaceWorkoutOrdering.accepts(
            incoming: surfaceWorkout(
                startedAt: start, capturedAt: now.addingTimeInterval(30)
            ), current: nil, terminal: nil, now: now
        ))
        XCTAssertFalse(ATHLTHSurfaceWorkoutOrdering.accepts(
            incoming: surfaceWorkout(
                startedAt: start,
                capturedAt: Date(timeIntervalSince1970: .infinity)
            ), current: nil, terminal: nil, now: now
        ))
    }

    func testOldWidgetSnapshotDecodesWithoutTerminalWatermark() throws {
        let oldJSON = """
        {"recoveryState":"Ready","updatedAt":0}
        """
        let old = try JSONDecoder().decode(
            ATHLTHSurfaceSnapshot.self, from: Data(oldJSON.utf8)
        )
        XCTAssertNil(old.lastFinishedWorkout)
        XCTAssertNil(old.activeWorkout)
    }

    func testFourByFourShowsActualEffortIntervals() {
        XCTAssertEqual(
            ATHLTHWidgetPresentationPolicy.intervalLabel(
                ordinal: 1, total: 4, isRecovery: false
            ), "1 av 4"
        )
        XCTAssertEqual(
            ATHLTHWidgetPresentationPolicy.intervalLabel(
                ordinal: 1, total: 4, isRecovery: true
            ), "Neste 2 av 4"
        )
        XCTAssertEqual(
            ATHLTHWidgetPresentationPolicy.intervalLabel(
                ordinal: 4, total: 4, isRecovery: true
            ), "Neste 4 av 4"
        )
    }

    func testFreeRunDoesNotInventIntervalCounter() {
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.intervalLabel(
            ordinal: nil, total: nil, isRecovery: false
        ))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.intervalLabel(
            ordinal: 1, total: 1, isRecovery: false
        ))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.intervalLabel(
            ordinal: 5, total: 4, isRecovery: false
        ))
    }

    func testCountdownRejectsInvalidSensorValues() {
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.remainingSeconds(.nan))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.remainingSeconds(.infinity))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.remainingSeconds(-3))
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.remainingSeconds(0), 0)
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.remainingSeconds(32), 32)
    }

    func testLongDurationIsNotTruncatedToMinutes() {
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.duration(90), "01:30")
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.duration(3_661), "1:01:01")
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.duration(0.2), "00:01")
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.duration(.nan), "00:00")
    }

    func testBadHeartRateAndDistanceAreNotDisplayed() {
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.heartRateLabel(.nan))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.heartRateLabel(0))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.distanceLabel(.infinity))
        XCTAssertNil(ATHLTHWidgetPresentationPolicy.distanceLabel(-12))
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.heartRateLabel(148), "148 bpm")
        XCTAssertEqual(ATHLTHWidgetPresentationPolicy.distanceLabel(5_250), "5.25 km")
    }
}
