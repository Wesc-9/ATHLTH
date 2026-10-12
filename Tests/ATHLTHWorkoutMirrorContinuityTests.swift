import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutMirrorContinuityTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(
        kind: WatchWorkoutKind = .running,
        state: WatchWorkoutMirrorState = .running
    ) -> WatchWorkoutLiveSnapshot {
        .init(
            kind: kind,
            state: state,
            startedAt: startedAt,
            capturedAt: startedAt.addingTimeInterval(180),
            elapsedTime: 180,
            heartRate: 151,
            activeCalories: 90,
            distanceMeters: 660,
            averageHeartRate: 145,
            maxHeartRate: 153,
            routePointCount: 24
        )
    }

    func testReattachingSameWatchWorkoutCanRetainMetrics() {
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: snapshot(),
            newKind: .running,
            newStartedAt: startedAt
        ))
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: snapshot(state: .paused),
            newKind: .running,
            newStartedAt: startedAt
        ))
    }

    func testNewWorkoutCannotInheritPreviousPulseOrDistance() {
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: snapshot(),
            newKind: .running,
            newStartedAt: startedAt.addingTimeInterval(15)
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: snapshot(),
            newKind: .walking,
            newStartedAt: startedAt
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: snapshot(state: .completed),
            newKind: .running,
            newStartedAt: startedAt
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: snapshot(),
            newKind: .running,
            newStartedAt: nil
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: nil,
            newKind: .running,
            newStartedAt: startedAt
        ))
    }

    func testOldHealthKitCallbacksCannotModifyNewMirroringSession() {
        let oldSession = NSObject()
        let newSession = NSObject()
        let oldID = ObjectIdentifier(oldSession)
        let newID = ObjectIdentifier(newSession)
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.acceptsDelegateCallback(
            activeSession: newID, incomingSession: newID
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsDelegateCallback(
            activeSession: newID, incomingSession: oldID
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsDelegateCallback(
            activeSession: nil, incomingSession: oldID
        ))
    }
}
