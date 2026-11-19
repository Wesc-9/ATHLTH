import Foundation
import HealthKit
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

    func testHealthKitSessionEndDoesNotPretendWorkoutWasSaved() {
        XCTAssertEqual(ATHLTHWorkoutMirrorStatePolicy.state(for: .stopped), .ending)
        XCTAssertEqual(ATHLTHWorkoutMirrorStatePolicy.state(for: .ended), .ending)
        XCTAssertEqual(ATHLTHWorkoutMirrorStatePolicy.state(for: .running), .running)
        XCTAssertEqual(ATHLTHWorkoutMirrorStatePolicy.state(for: .paused), .paused)
        XCTAssertNotEqual(ATHLTHWorkoutMirrorStatePolicy.state(for: .ended), .completed)
    }

    func testCompletionBelongsToExactWorkoutRatherThanAnotherNearbyRun() {
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
            snapshot: snapshot(), kind: .running, startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60)
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
            snapshot: snapshot(), kind: .running, startedAt: startedAt.addingTimeInterval(-15),
            endedAt: startedAt.addingTimeInterval(-5)
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
            snapshot: snapshot(), kind: .running, startedAt: startedAt.addingTimeInterval(-15),
            endedAt: startedAt.addingTimeInterval(5)
        ))
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

    func testWatchStrengthMirrorFinishesOnlyMatchingSession() {
        let id = UUID()
        var completed = snapshot(kind: .strength, state: .completed)
        completed.strengthWorkoutID = id

        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.canFinishStrength(
            snapshot: completed, workoutID: id,
            workoutStartedAt: startedAt
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.canFinishStrength(
            snapshot: completed, workoutID: UUID(),
            workoutStartedAt: startedAt
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.canFinishStrength(
            snapshot: completed, workoutID: id,
            workoutStartedAt: startedAt.addingTimeInterval(120)
        ))
        completed.strengthWorkoutID = nil
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.canFinishStrength(
            snapshot: completed, workoutID: id,
            workoutStartedAt: startedAt.addingTimeInterval(5)
        ), "An older Watch without stable IDs can still finish when clocks agree")
        completed.startedAt = nil
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.canFinishStrength(
            snapshot: completed, workoutID: id,
            workoutStartedAt: startedAt
        ))
    }

    func testWatchMirrorRejectsDifferentStrengthIDsEvenWhenTimestampsAgree() {
        var original = snapshot(kind: .strength)
        original.strengthWorkoutID = UUID()
        var incoming = original
        incoming.capturedAt = original.capturedAt.addingTimeInterval(5)
        incoming.strengthWorkoutID = UUID()
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
            previous: original, incoming: incoming
        ))
    }

    func testWatchMirrorRejectsOlderBatchAndOtherWorkouts() {
        let current = snapshot()
        var older = snapshot()
        older.capturedAt = current.capturedAt.addingTimeInterval(-5)
        older.state = .paused
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
            previous: current, incoming: older
        ))

        var later = snapshot()
        later.capturedAt = current.capturedAt.addingTimeInterval(1)
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
            previous: current, incoming: later
        ))

        later.startedAt = startedAt.addingTimeInterval(25)
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
            previous: current, incoming: later
        ))
        later.startedAt = startedAt
        later.kind = .walking
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
            previous: current, incoming: later
        ))
    }

    func testWatchMirrorCannotReenterRunningAfterEnding() {
        let ending = snapshot(state: .ending)
        var late = snapshot(state: .running)
        late.capturedAt = ending.capturedAt.addingTimeInterval(1)
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
            previous: ending, incoming: late
        ))
        late.state = .completed
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
            previous: ending, incoming: late
        ))
    }

    func testWatchMirrorCannotResurrectCompletedSession() {
        let completed = snapshot(state: .completed)
        var late = snapshot()
        late.capturedAt = completed.capturedAt.addingTimeInterval(10)
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
            previous: completed, incoming: late
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
            previous: nil, incoming: lateWithInvalidClock(late)
        ))
    }

    private func lateWithInvalidClock(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) -> WatchWorkoutLiveSnapshot {
        var copy = snapshot
        copy.capturedAt = Date(timeIntervalSince1970: .infinity)
        return copy
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
