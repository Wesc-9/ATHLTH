import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHStabilityBoundaryTests: XCTestCase {
    func testSharedClockRejectsInvalidDates() {
        let valid = Date(timeIntervalSince1970: 100)
        let invalid = Date(timeIntervalSince1970: .infinity)
        XCTAssertNil(ATHLTHWorkoutSessionClock.finiteInterval(from: valid, to: invalid))
        XCTAssertEqual(ATHLTHWorkoutSessionClock.elapsed(activeBeforeResume: 12, resumedAt: valid, at: invalid), 12)
        XCTAssertNil(ATHLTHStructuredWorkoutClock.elapsed(start: valid, now: invalid, pause: nil, pausedSeconds: 0))
    }

    func testSharedClockPreservesOvertimeAndPausedElapsed() {
        let start = Date(timeIntervalSince1970: 100)
        let end = Date(timeIntervalSince1970: 115)
        XCTAssertEqual(ATHLTHWorkoutSessionClock.remaining(secondsAtPause: 10, resumedAt: start, at: end), -5)
        XCTAssertEqual(ATHLTHWorkoutSessionClock.elapsed(activeBeforeResume: 12, resumedAt: nil, at: end), 12)
        XCTAssertEqual(ATHLTHStructuredWorkoutClock.elapsed(start: start, now: end, pause: nil, pausedSeconds: 3), 12)
    }

    func testExtremeStageIndexIsRejectedWithoutOverflow() {
        let id = UUID()
        XCTAssertNil(ATHLTHWorkoutLifecyclePolicy.nextPhase(
            for: .advance, workoutID: id, expectedWorkoutID: id,
            source: .structuredTimer, recordingOwner: .iPhone,
            phase: .work, stageIndex: Int.max, stageCount: Int.max
        ))
    }

    func testDelayedNavigationIdentityAcceptsNonFiniteInput() {
        let plan = UUID()
        let workout = UUID()
        for seconds in [Double.infinity, -Double.infinity, Double.nan, Double.greatestFiniteMagnitude] {
            let request = ATHLTHTrainNavigationRequest.startPlannedWorkoutAfter(
                planID: plan, workoutID: workout, seconds: seconds
            )
            XCTAssertFalse(request.id.isEmpty)
        }
    }

    func testDelayedNavigationPreservesFractionalIdentity() {
        let plan = UUID()
        let workout = UUID()
        XCTAssertNotEqual(
            ATHLTHTrainNavigationRequest.startPlannedWorkoutAfter(planID: plan, workoutID: workout, seconds: 1.1).id,
            ATHLTHTrainNavigationRequest.startPlannedWorkoutAfter(planID: plan, workoutID: workout, seconds: 1.9).id
        )
    }
}
