import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHRunIntervalReadoutTests: XCTestCase {
    private func step(
        measure: WatchRunningStepMeasure,
        durationSeconds: TimeInterval? = nil,
        distanceMeters: Double? = nil
    ) -> WatchRunningWorkoutStep {
        WatchRunningWorkoutStep(
            id: UUID(),
            title: "Work interval",
            measure: measure,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            intensityText: nil
        )
    }

    func testStructuredRunCountdownAlwaysShowsHoursMinutesSeconds() {
        XCTAssertEqual(ATHLTHRunStepCountdown.display(582), "00:09:42")
        XCTAssertEqual(ATHLTHRunStepCountdown.display(3_723), "01:02:03")
        XCTAssertEqual(ATHLTHRunStepCountdown.display(0), "00:00:00")
        XCTAssertEqual(ATHLTHRunStepCountdown.display(0.25), "00:00:01")
        XCTAssertEqual(ATHLTHRunStepCountdown.display(-2), "00:00:00")
    }

    func testTimedStepEndsAtExactTargetNotOneSecondAfter() {
        let effort = step(measure: .time, durationSeconds: 240)
        XCTAssertFalse(ATHLTHRunningStepEngine.isCompleted(
            step: effort, elapsedTime: 239.999,
            distanceMeters: 0, stepStartElapsedTime: 0,
            stepStartDistanceMeters: 0
        ))
        XCTAssertTrue(ATHLTHRunningStepEngine.isCompleted(
            step: effort, elapsedTime: 240,
            distanceMeters: 0, stepStartElapsedTime: 0,
            stepStartDistanceMeters: 0
        ))
    }

    func testTimedIntervalShowsRemainingNotElapsed() {
        let readout = ATHLTHRunIntervalReadout.resolve(
            step: step(measure: .time, durationSeconds: 120),
            elapsedSeconds: 45,
            distanceMeters: 500
        )
        XCTAssertEqual(readout.unit, .seconds)
        XCTAssertEqual(readout.remaining ?? -1, 75, accuracy: 0.0001)
        XCTAssertEqual(readout.progress ?? -1, 0.375, accuracy: 0.0001)
    }

    func testDistanceIntervalUsesStepDistanceOnly() {
        let readout = ATHLTHRunIntervalReadout.resolve(
            step: step(measure: .distance, distanceMeters: 1_000),
            elapsedSeconds: 600,
            distanceMeters: 350
        )
        XCTAssertEqual(readout.unit, .meters)
        XCTAssertEqual(readout.remaining ?? -1, 650, accuracy: 0.0001)
        XCTAssertEqual(readout.progress ?? -1, 0.35, accuracy: 0.0001)
    }

    func testCompletedIntervalNeverShowsNegativeRemaining() {
        let readout = ATHLTHRunIntervalReadout.resolve(
            step: step(measure: .time, durationSeconds: 60),
            elapsedSeconds: 80,
            distanceMeters: 0
        )
        XCTAssertEqual(readout.remaining, 0)
        XCTAssertEqual(readout.progress, 1)
    }

    func testOpenIntervalDoesNotInventADeadline() {
        let readout = ATHLTHRunIntervalReadout.resolve(
            step: step(measure: .open),
            elapsedSeconds: 60,
            distanceMeters: 100
        )
        XCTAssertEqual(readout.unit, .open)
        XCTAssertNil(readout.remaining)
        XCTAssertNil(readout.progress)
    }

    func testInvalidIntervalTargetDoesNotDivideByZero() {
        let readout = ATHLTHRunIntervalReadout.resolve(
            step: step(measure: .time, durationSeconds: 0),
            elapsedSeconds: 35,
            distanceMeters: 0
        )
        XCTAssertNil(readout.remaining)
        XCTAssertNil(readout.progress)
    }

    func testPulseTargetNeedsValidMeasurement() {
        XCTAssertEqual(
            ATHLTHRunPulseTargetStatus.resolve(
                heartRate: 0, minimum: 130, maximum: 155
            ),
            .waiting
        )
        XCTAssertEqual(
            ATHLTHRunPulseTargetStatus.resolve(
                heartRate: nil, minimum: 130, maximum: 155
            ),
            .waiting
        )
    }

    func testPulseTargetBoundariesAreInclusive() {
        for bpm in [130.0, 145, 155] {
            XCTAssertEqual(
                ATHLTHRunPulseTargetStatus.resolve(
                    heartRate: bpm, minimum: 130, maximum: 155
                ),
                .within
            )
        }
        XCTAssertEqual(
            ATHLTHRunPulseTargetStatus.resolve(
                heartRate: 129, minimum: 130, maximum: 155
            ),
            .below
        )
        XCTAssertEqual(
            ATHLTHRunPulseTargetStatus.resolve(
                heartRate: 156, minimum: 130, maximum: 155
            ),
            .above
        )
    }

    func testInvalidPulseTargetsCannotClaimWithinZone() {
        XCTAssertEqual(
            ATHLTHRunPulseTargetStatus.resolve(
                heartRate: 145, minimum: 160, maximum: 130
            ),
            .unavailable
        )
        XCTAssertEqual(
            ATHLTHRunPulseTargetStatus.resolve(
                heartRate: .nan, minimum: 130, maximum: 155
            ),
            .waiting
        )
    }

    func testDelayedOrPausedGhostCannotBeShownAsLive() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var ghost = ATHLTHLiveGhostContext(
            title: "Arena",
            distanceDeltaMeters: 72,
            estimatedTimeDeltaSeconds: 16,
            updatedAt: now
        )
        ghost.connectionText = "LIVE"
        XCTAssertEqual(
            ATHLTHLiveGhostWatchSignal.resolve(
                context: ghost, isPaused: false, now: now
            ),
            .live
        )
        XCTAssertEqual(
            ATHLTHLiveGhostWatchSignal.resolve(
                context: ghost, isPaused: true, now: now
            ),
            .paused
        )
        XCTAssertEqual(
            ATHLTHLiveGhostWatchSignal.resolve(
                context: ghost,
                isPaused: false,
                now: now.addingTimeInterval(20)
            ),
            .delayed
        )
    }
}
