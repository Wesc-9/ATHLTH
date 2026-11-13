import Foundation
import XCTest
@testable import ATHLTH

/// The iPad live companion is a spectator, never a second workout recorder.
/// Missing metrics stay unknown and counters do not run on after sync stalls.
final class ATHLTHiPadLiveWorkoutTests: XCTestCase {
    private func snapshot(
        paused: Bool? = false,
        elapsed: TimeInterval = 540,
        capturedAt: Date? = Date(timeIntervalSince1970: 1_000),
        stepRemaining: TimeInterval? = 70
    ) -> ATHLTHCrossDeviceWorkoutSnapshot {
        ATHLTHCrossDeviceWorkoutSnapshot(
            sessionID: UUID(),
            kind: "running",
            title: "4 × 4",
            startedAt: Date(timeIntervalSince1970: 460),
            elapsedSeconds: elapsed,
            distanceMeters: 1_400,
            currentStep: "Effort 2",
            nextStep: "Recovery",
            completedSets: nil,
            totalSets: nil,
            paused: paused,
            runningIntervalOrdinal: 2,
            runningIntervalTotal: 4,
            runningInRecovery: false,
            runningStepRemainingSeconds: stepRemaining,
            capturedAt: capturedAt
        )
    }

    func testTimerExtrapolatesOnlyBrieflyAndNeverPastSourceTTL() {
        let now = Date(timeIntervalSince1970: 1_020)
        let remote = snapshot()
        XCTAssertEqual(ATHLTHiPadLiveMetrics.elapsed(remote, at: now), 548)
        XCTAssertEqual(ATHLTHiPadLiveMetrics.remaining(remote, at: now), 62)
        XCTAssertTrue(ATHLTHiPadLiveMetrics.isDelayed(remote, at: now))
        XCTAssertEqual(ATHLTHiPadLiveMetrics.duration(548), "09:08")
    }

    func testPausePreservesRecordedElapsedAndCountdown() {
        let now = Date(timeIntervalSince1970: 1_030)
        let paused = snapshot(paused: true)
        XCTAssertEqual(ATHLTHiPadLiveMetrics.elapsed(paused, at: now), 540)
        XCTAssertEqual(ATHLTHiPadLiveMetrics.remaining(paused, at: now), 70)
    }

    func testMissingSensorDataDoesNotInventNumbers() {
        XCTAssertEqual(ATHLTHiPadLiveMetrics.heartRate(nil), "—")
        XCTAssertEqual(ATHLTHiPadLiveMetrics.pace(nil), "—")
        XCTAssertEqual(ATHLTHiPadLiveMetrics.calories(nil), "—")
        XCTAssertEqual(ATHLTHiPadLiveMetrics.distance(nil), "—")
        XCTAssertNil(ATHLTHiPadLiveMetrics.normalized(Double.nan))
        XCTAssertNil(ATHLTHiPadLiveMetrics.normalized(5))
    }

    func testAveragePaceUsesActualDistanceAndElapsed() {
        let workout = snapshot(elapsed: 600)
        XCTAssertEqual(ATHLTHiPadLiveMetrics.averagePace(workout), "7:09")
        XCTAssertEqual(ATHLTHiPadLiveMetrics.pace(300), "5:00")
    }

    func testOlderPrivateSnapshotDecodesWithoutNewOptionalTelemetry() throws {
        let original = snapshot()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            ATHLTHCrossDeviceWorkoutSnapshot.self, from: encoded
        )
        XCTAssertNil(decoded.sourceDevice)
        XCTAssertNil(decoded.heartRateBPM)
        XCTAssertNil(decoded.currentPaceSecondsPerKilometer)
        XCTAssertEqual(decoded.elapsedSeconds, 540)
        XCTAssertEqual(decoded.runningIntervalOrdinal, 2)
    }

    func testStrengthSetsAreReadOnlyAndNeverExceedTotal() {
        var workout = snapshot()
        workout.completedSets = 12
        workout.totalSets = 10
        XCTAssertEqual(ATHLTHiPadLiveMetrics.sets(workout), "10 / 10")
    }
}
