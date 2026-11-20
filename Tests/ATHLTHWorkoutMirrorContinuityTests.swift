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

    func testWatchStrengthCompletionMustMatchStableMirroredIdentity() {
        let original = UUID()
        var mirrored = snapshot(kind: .strength)
        mirrored.strengthWorkoutID = original
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
            snapshot: mirrored, kind: .strength,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            strengthWorkoutID: original
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
            snapshot: mirrored, kind: .strength,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            strengthWorkoutID: UUID()
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
            snapshot: mirrored, kind: .strength,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60)
        ), "A result missing the strength ID must not end a newer mirror")
        mirrored.strengthWorkoutID = nil
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
            snapshot: mirrored, kind: .strength,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60)
        ), "Legacy Watch snapshots without stable IDs retain the time guard")
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
            snapshot: mirrored, kind: .strength,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(-1)
        ), "A result cannot finish before its own start")
    }

    func testOldInactiveWatchResponseCannotEndNewerMirror() {
        let live = snapshot(kind: .running)
        let oldInactive = WatchWorkoutActivityState(
            isActive: false, title: nil,
            updatedAt: live.capturedAt.addingTimeInterval(-15)
        )
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsInactiveWatchActivity(
            snapshot: live, activity: oldInactive
        ), "A late status from the previous workout cannot close newer live data")

        let confirmedInactive = WatchWorkoutActivityState(
            isActive: false, title: nil,
            updatedAt: live.capturedAt.addingTimeInterval(1)
        )
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.acceptsInactiveWatchActivity(
            snapshot: live, activity: confirmedInactive
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsInactiveWatchActivity(
            snapshot: live,
            activity: WatchWorkoutActivityState(
                isActive: true, title: nil,
                updatedAt: live.capturedAt.addingTimeInterval(1)
            )
        ))
        var completed = live
        completed.state = .completed
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsInactiveWatchActivity(
            snapshot: completed, activity: confirmedInactive
        ))
        var missingStart = live
        missingStart.startedAt = nil
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsInactiveWatchActivity(
            snapshot: missingStart, activity: confirmedInactive
        ))
    }

    func testReattachingSameWatchWorkoutCanRetainMetrics() {
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: snapshot(),
            newKind: .running,
            newStartedAt: startedAt,
            sameHealthKitSession: true
        ))
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: snapshot(state: .paused),
            newKind: .running,
            newStartedAt: startedAt,
            sameHealthKitSession: true
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

    func testInactiveWatchStatusEndsPresentationWithoutClaimingSavedResult() {
        let run = snapshot(kind: .running)
        let strength = snapshot(kind: .strength)
        let pending = snapshot(kind: .strength, state: .ending)
        XCTAssertEqual(
            ATHLTHWorkoutMirrorContinuity.stateAfterInactiveWatchActivity(run),
            .ending
        )
        XCTAssertEqual(
            ATHLTHWorkoutMirrorContinuity.stateAfterInactiveWatchActivity(strength),
            .ending
        )
        XCTAssertEqual(
            ATHLTHWorkoutMirrorContinuity.stateAfterInactiveWatchActivity(pending),
            .ending
        )
        XCTAssertNotEqual(
            ATHLTHWorkoutMirrorContinuity.stateAfterInactiveWatchActivity(strength),
            .completed,
            "Watch inactive is not evidence that its HealthKit result was saved"
        )
        // A later, correlated persisted Watch result can still finish the
        // same session after the inactive indicator stopped the live UI.
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
            snapshot: pending, kind: .strength,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(181)
        ))
    }

    func testKnownStrengthIdentityRejectsUnidentifiedLaterLiveSnapshot() {
        var original = snapshot(kind: .strength)
        original.strengthWorkoutID = UUID()
        var late = original
        late.strengthWorkoutID = nil
        late.capturedAt = original.capturedAt.addingTimeInterval(1)
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
            previous: original, incoming: late
        ))
        late.strengthWorkoutID = original.strengthWorkoutID
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
            previous: original, incoming: late
        ))
    }

    func testActiveMirrorRejectsLaterPacketWithoutWorkoutStart() {
        let original = snapshot(kind: .walking)
        var missingStart = original
        missingStart.startedAt = nil
        missingStart.capturedAt = original.capturedAt.addingTimeInterval(2)
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
            previous: original, incoming: missingStart
        ))
        // A legacy preparing session, before any start time is known, may
        // still move into its first recorded start.
        var preparing = snapshot(state: .preparing)
        preparing.startedAt = nil
        var first = preparing
        first.startedAt = startedAt
        first.state = .running
        first.capturedAt = preparing.capturedAt.addingTimeInterval(1)
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
            previous: preparing, incoming: first
        ))
    }

    func testWatchUniversalIdentityRejectsCrossWorkoutLiveReplayForEverySport() {
        for kind: WatchWorkoutKind in [
            .running, .walking, .cycling, .rowing, .stairClimbing,
            .hiit, .functional, .yoga, .other
        ] {
            var previous = snapshot(kind: kind)
            previous.universalWorkoutID = UUID()
            var incoming = previous
            incoming.capturedAt = previous.capturedAt.addingTimeInterval(1)
            XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
                previous: previous, incoming: incoming
            ))
            incoming.universalWorkoutID = UUID()
            XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
                previous: previous, incoming: incoming
            ))
            incoming.universalWorkoutID = nil
            XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot(
                previous: previous, incoming: incoming
            ))
        }
    }

    func testWatchCompletionRequiresSameOriginalUniversalWorkoutID() {
        var original = snapshot(kind: .cycling)
        original.universalWorkoutID = UUID()
        let end = startedAt.addingTimeInterval(201)
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
            snapshot: original, kind: .cycling,
            startedAt: startedAt, endedAt: end
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
            snapshot: original, kind: .cycling,
            startedAt: startedAt, endedAt: end,
            universalWorkoutID: UUID()
        ))
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
            snapshot: original, kind: .cycling,
            startedAt: startedAt, endedAt: end,
            universalWorkoutID: original.universalWorkoutID
        ))
        var old = snapshot(kind: .cycling)
        old.universalWorkoutID = nil
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
            snapshot: old, kind: .cycling,
            startedAt: startedAt, endedAt: end
        ), "Older Watch snapshots keep their existing time-gated fallback")
    }

    func testStrengthUniversalIDMustAgreeWithOriginalStrengthLog() {
        var original = snapshot(kind: .strength, state: .completed)
        original.strengthWorkoutID = UUID()
        original.universalWorkoutID = UUID()
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.canFinishStrength(
            snapshot: original, workoutID: original.strengthWorkoutID!,
            workoutStartedAt: startedAt
        ))
        original.universalWorkoutID = original.strengthWorkoutID
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.canFinishStrength(
            snapshot: original, workoutID: original.strengthWorkoutID!,
            workoutStartedAt: startedAt
        ))
    }


    func testWatchDelegateAndBuilderCallbacksRequireTheOriginalSession() {
        // Events are queued between HealthKit's delegate queue and MainActor.
        // Session A must not stop/alter B after a restart or recovery.
        let old = NSObject(), current = NSObject()
        for incoming: ObjectIdentifier? in [
            ObjectIdentifier(old), nil
        ] {
            XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsDelegateCallback(
                activeSession: ObjectIdentifier(current),
                incomingSession: incoming ?? ObjectIdentifier(old)
            ))
        }
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.acceptsDelegateCallback(
            activeSession: ObjectIdentifier(current),
            incomingSession: ObjectIdentifier(current)
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.acceptsDelegateCallback(
            activeSession: nil,
            incomingSession: ObjectIdentifier(current)
        ))
    }

    func testPreparedWatchLaunchPreflightIsExclusiveUntilReleased() {
        XCTAssertTrue(ATHLTHWatchPreparedLaunchReservationPolicy.mayBegin(
            pendingID: nil
        ))
        for kind in WatchWorkoutKind.allCases {
            XCTAssertFalse(ATHLTHWatchPreparedLaunchReservationPolicy.mayBegin(
                pendingID: UUID()
            ), "Concurrent prepared launch must be rejected: \\(kind.rawValue)")
        }
        // After the originating async launch returns, that reservation can
        // be released even on denied authorization or failed HealthKit start.
        XCTAssertTrue(ATHLTHWatchPreparedLaunchReservationPolicy.mayBegin(
            pendingID: nil
        ))
    }

    func testEveryWatchHealthKitStartPathSharesTransientPreflightAdmission() {
        XCTAssertTrue(ATHLTHWatchStartPreflightAdmissionPolicy.canReserve(
            pendingID: nil
        ))
        let existing = UUID()
        for _ in WatchWorkoutKind.allCases {
            XCTAssertFalse(ATHLTHWatchStartPreflightAdmissionPolicy.canReserve(
                pendingID: existing
            ), "Concurrent manual, prepared and remote Watch starts must be rejected")
        }
        XCTAssertTrue(ATHLTHWatchStartPreflightAdmissionPolicy.canReserve(
            pendingID: nil
        ), "Admission must be released after all async start outcomes")
    }

    func testWatchMirrorMutationsRequireOriginalIDAndMatchingStart() throws {
        let originalID = UUID()
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        for type: WatchWorkoutCommand in [
            .pause, .resume, .end, .setTreadmillIncline,
            .setTreadmillTargetPace, .setTreadmillBeltSpeed,
            .returnToStart, .advanceRunningStep, .appendRunningWorkout
        ] {
            var command = WatchWorkoutMirrorCommand(
                command: type, workoutStartedAt: start,
                universalWorkoutID: originalID
            )
            XCTAssertTrue(ATHLTHWatchMirrorCommandAdmission.permits(
                command, currentStartedAt: start,
                currentWorkoutID: originalID
            ), "Valid current command: \\(type.rawValue)")
            command.universalWorkoutID = UUID()
            XCTAssertFalse(ATHLTHWatchMirrorCommandAdmission.permits(
                command, currentStartedAt: start,
                currentWorkoutID: originalID
            ))
            command.universalWorkoutID = nil
            XCTAssertFalse(ATHLTHWatchMirrorCommandAdmission.permits(
                command, currentStartedAt: start,
                currentWorkoutID: originalID
            ), "Missing ID must not downgrade a known recorder")
            command.universalWorkoutID = originalID
            command.workoutStartedAt = start.addingTimeInterval(-15)
            XCTAssertFalse(ATHLTHWatchMirrorCommandAdmission.permits(
                command, currentStartedAt: start,
                currentWorkoutID: originalID
            ), "Queued command from an older workout must not change this one")
            command.workoutStartedAt = nil
            XCTAssertFalse(ATHLTHWatchMirrorCommandAdmission.permits(
                command, currentStartedAt: start,
                currentWorkoutID: originalID
            ))
        }
    }

    func testMirroredMutationRoundTripKeepsOriginalIdentity() throws {
        let originalID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let command = WatchWorkoutMirrorCommand(
            command: .end, workoutStartedAt: startedAt,
            universalWorkoutID: originalID
        )
        let decoded = try JSONDecoder().decode(
            WatchWorkoutMirrorCommand.self,
            from: JSONEncoder().encode(command)
        )
        XCTAssertEqual(decoded.universalWorkoutID, originalID)
        XCTAssertTrue(ATHLTHWatchMirrorCommandAdmission.permits(
            decoded, currentStartedAt: startedAt,
            currentWorkoutID: originalID
        ))
        // Legacy commands remain decodable but cannot mutate a modern
        // session without its original identity and start.
        let legacy = try JSONDecoder().decode(
            WatchWorkoutMirrorCommand.self,
            from: JSONEncoder().encode(
                WatchWorkoutMirrorCommand(command: .end)
            )
        )
        XCTAssertNil(legacy.universalWorkoutID)
        XCTAssertFalse(ATHLTHWatchMirrorCommandAdmission.permits(
            legacy, currentStartedAt: startedAt,
            currentWorkoutID: originalID
        ))
        let legacyStartOnly = WatchWorkoutMirrorCommand(
            command: .pause, workoutStartedAt: startedAt
        )
        XCTAssertTrue(ATHLTHWatchMirrorCommandAdmission.permits(
            legacyStartOnly, currentStartedAt: startedAt,
            currentWorkoutID: nil
        ), "Unidentified restored legacy session uses strict clock fallback")
        XCTAssertFalse(ATHLTHWatchMirrorCommandAdmission.permits(
            command, currentStartedAt: startedAt,
            currentWorkoutID: nil
        ), "Never downgrade a known sender to an unknown receiver")
    }

    func testReconnectedSessionNeverInheritsUnverifiedWatchSensorValues() {
        let previous = snapshot()
        // Two newly created HealthKit sessions can start in the same
        // second and report the same sport. Time similarity is not proof
        // that old pulse, calories or distance belong to the new workout.
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: previous, newKind: .running,
            newStartedAt: startedAt, sameHealthKitSession: false
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: previous, newKind: .running,
            newStartedAt: startedAt
        ))
        XCTAssertTrue(ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: previous, newKind: .running,
            newStartedAt: startedAt, sameHealthKitSession: true
        ))
        XCTAssertFalse(ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: previous, newKind: .walking,
            newStartedAt: startedAt, sameHealthKitSession: true
        ))
    }

}
