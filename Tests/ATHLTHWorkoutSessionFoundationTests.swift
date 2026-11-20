import Foundation
import XCTest
@testable import ATHLTH

/// Phase 1 guardrails: a normalized session must not add a HealthKit session,
/// rewrite an existing set, or move a lock-screen clock independently.
final class ATHLTHWorkoutSessionFoundationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_900_000_000)

    private func phone(walking: Bool = false) -> PhoneWorkout {
        PhoneWorkout(
            walking: walking,
            start: start,
            resumedAt: start,
            lastCheckpoint: start
        )
    }

    @MainActor
    func testEveryNativeWatchSportReservesOneCrossActivityStartUntilReleased() throws {
        let phone = IPhoneWorkoutStore()
        let strength = StrengthWorkoutStore()
        XCTAssertNil(phone.active)
        XCTAssertNil(strength.activeWorkout)
        for kind in WatchWorkoutKind.allCases {
            let reservation = try ATHLTHWorkoutRecordingArbiter.reserveLaunch()
            XCTAssertTrue(ATHLTHWorkoutRecordingArbiter.hasPendingLaunch,
                          kind.rawValue)
            XCTAssertFalse(ATHLTHWorkoutRecordingArbiter.mayStartRunning(),
                           "An unrelated phone run may not borrow Watch launch")
            XCTAssertFalse(ATHLTHWorkoutRecordingArbiter.mayStartStrength(),
                           "An unrelated strength start may not borrow Watch launch")
            XCTAssertFalse(ATHLTHWorkoutRecordingArbiter.mayStartRunning(
                admissionID: UUID()
            ))
            XCTAssertFalse(ATHLTHWorkoutRecordingArbiter.mayStartStrength(
                admissionID: UUID()
            ))
            XCTAssertTrue(ATHLTHWorkoutRecordingArbiter.mayStartRunning(
                admissionID: reservation
            ))
            XCTAssertTrue(ATHLTHWorkoutRecordingArbiter.mayStartStrength(
                admissionID: reservation
            ))
            XCTAssertThrowsError(try ATHLTHWorkoutRecordingArbiter.reserveLaunch(),
                                 "Different Watch kinds must share a launch slot")
            ATHLTHWorkoutRecordingArbiter.releaseLaunch(UUID())
            XCTAssertTrue(ATHLTHWorkoutRecordingArbiter.hasPendingLaunch)
            ATHLTHWorkoutRecordingArbiter.releaseLaunch(reservation)
            XCTAssertFalse(ATHLTHWorkoutRecordingArbiter.hasPendingLaunch)
            XCTAssertFalse(ATHLTHWorkoutRecordingArbiter.mayStartRunning(
                admissionID: reservation
            ))
            XCTAssertFalse(ATHLTHWorkoutRecordingArbiter.mayStartStrength(
                admissionID: reservation
            ))
            XCTAssertTrue(ATHLTHWorkoutRecordingArbiter.mayStartRunning())
            XCTAssertTrue(ATHLTHWorkoutRecordingArbiter.mayStartStrength())
        }
    }

    func testRemoteRelayRejectsExpiredAndMismatchedClaims() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        func accepted(
            source: String = "ipad",
            target: String = "apple_watch",
            kind: String = "run",
            payloadTarget: String = "apple_watch",
            payloadKind: String = "run",
            version: Int = 1,
            expiry: TimeInterval = 60,
            claimedDeviceID: String? = "test-iphone",
            expectedDeviceID: String = "test-iphone",
            completedAt: Date? = nil,
            failedAt: Date? = nil
        ) -> Bool {
            WorkoutDeviceRelayClaimPolicy.accepts(
                source: source, target: target, kind: kind,
                payloadTarget: payloadTarget, payloadKind: payloadKind,
                payloadVersion: version,
                expiresAt: now.addingTimeInterval(expiry),
                claimedDeviceID: claimedDeviceID,
                expectedDeviceID: expectedDeviceID,
                completedAt: completedAt, failedAt: failedAt, now: now
            )
        }
        XCTAssertTrue(accepted())
        XCTAssertFalse(accepted(source: "iphone"))
        XCTAssertFalse(accepted(target: "iphone"))
        XCTAssertFalse(accepted(kind: "strength"))
        XCTAssertFalse(accepted(payloadTarget: "iphone"))
        XCTAssertFalse(accepted(payloadKind: "walk"))
        XCTAssertFalse(accepted(version: 2))
        XCTAssertFalse(accepted(expiry: 0))
        XCTAssertFalse(accepted(expiry: -1))
        XCTAssertFalse(accepted(claimedDeviceID: nil))
        XCTAssertFalse(accepted(claimedDeviceID: "another-iphone"))
        XCTAssertFalse(accepted(expectedDeviceID: ""))
        XCTAssertFalse(accepted(completedAt: now))
        XCTAssertFalse(accepted(failedAt: now))
    }

    func testConcurrentManualStrengthHealthWritesHaveOneOwner() {
        let workoutID = UUID()
        let otherWorkoutID = UUID()
        var gate = ATHLTHManualStrengthWorkoutWriteGate()
        XCTAssertTrue(gate.reserve(workoutID))
        XCTAssertFalse(gate.reserve(workoutID))
        XCTAssertTrue(gate.reserve(otherWorkoutID))
        gate.release(workoutID)
        XCTAssertTrue(gate.reserve(workoutID),
                      "A failed first write may be retried")
        XCTAssertFalse(gate.reserve(workoutID))
        gate.release(otherWorkoutID)
        gate.release(workoutID)
        XCTAssertTrue(gate.reserve(workoutID))
    }

    func testSharedActiveClockMatchesExistingRunningElapsed() {
        var workout = phone()
        let later = start.addingTimeInterval(90)
        XCTAssertEqual(workout.elapsed(at: later), 90, accuracy: 0.001)

        // Restore a paused workout from its persisted checkpoint. Neither
        // session nor pace advance while the phone is backgrounded.
        workout.accumulatedSeconds = 90
        workout.resumedAt = nil
        XCTAssertEqual(workout.elapsed(at: start.addingTimeInterval(600)),
                       90, accuracy: 0.001)

        workout.resumedAt = start.addingTimeInterval(600)
        XCTAssertEqual(workout.elapsed(at: start.addingTimeInterval(650)),
                       140, accuracy: 0.001)
    }

    func testRecoveredRunAndWalkFinishAtRealTimeWithoutAddingIdleMinutes() {
        let checkpointAt = start.addingTimeInterval(85)
        let finishedAt = start.addingTimeInterval(3600)
        for walking in [false, true] {
            var recovered = phone(walking: walking)
            recovered.accumulatedSeconds = 85
            recovered.resumedAt = nil
            recovered.lastCheckpoint = checkpointAt
            recovered.pauses = [
                PhoneWorkoutPauseInterval(startedAt: checkpointAt, endedAt: nil)
            ]
            recovered.end = ATHLTHWorkoutSessionFoundation.completionTimestamp(
                startedAt: recovered.start, finishedAt: finishedAt
            )
            XCTAssertEqual(recovered.end, finishedAt)
            XCTAssertEqual(recovered.elapsed(at: finishedAt), 85, accuracy: 0.001)
            XCTAssertNotEqual(recovered.end, checkpointAt)
        }
    }

    @MainActor
    func testRecoveredStrengthAndHybridSessionTimeStopsWhilePhoneIsSuspended() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        var workout = try XCTUnwrap(store.activeWorkout)
        let started = workout.startedAt
        let checkpoint = started.addingTimeInterval(45)
        let reopened = started.addingTimeInterval(3_600)

        XCTAssertEqual(workout.elapsedSessionSeconds(
            at: reopened, suspendedAt: checkpoint
        ), 45, accuracy: 0.001)
        let paused = ATHLTHWorkoutSessionFoundation.strength(
            workout, exerciseIndex: 0, isResting: false,
            suspendedAt: checkpoint, at: reopened
        )
        XCTAssertEqual(paused.phase, .paused)
        XCTAssertEqual(paused.activeElapsedSeconds, 45, accuracy: 0.001)

        workout.excludedRecoverySeconds = reopened.timeIntervalSince(checkpoint)
        XCTAssertEqual(workout.elapsedSessionSeconds(
            at: reopened.addingTimeInterval(20)
        ), 65, accuracy: 0.001)
        let resumed = ATHLTHWorkoutSessionFoundation.strength(
            workout, exerciseIndex: 0, isResting: false,
            at: reopened.addingTimeInterval(20)
        )
        XCTAssertEqual(resumed.phase, .work)
        XCTAssertEqual(resumed.activeElapsedSeconds, 65, accuracy: 0.001)

        // The same normalized session remains one strength/hybrid workout,
        // even when an embedded running exercise controls its visible UI.
        XCTAssertEqual(paused.workoutID, resumed.workoutID)
        XCTAssertEqual(paused.recordingOwner, .iPhone)
    }

    @MainActor
    func testRecoveredPhoneStrengthPauseEventsRemainDeduplicated() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        var workout = try XCTUnwrap(store.activeWorkout)
        let start = workout.startedAt

        let first = start.addingTimeInterval(80)
        let resumed = start.addingTimeInterval(400)
        workout.recordRecoveredDowntime(from: first, until: resumed)
        XCTAssertEqual(workout.excludedRecoverySeconds ?? 0, 320, accuracy: 0.001)
        XCTAssertEqual(workout.recoveryPauseIntervals?.count, 1)
        workout.recordRecoveredDowntime(
            from: first.addingTimeInterval(10),
            until: resumed.addingTimeInterval(30)
        )
        XCTAssertEqual(workout.excludedRecoverySeconds ?? 0, 350, accuracy: 0.001)
        XCTAssertEqual(workout.recoveryPauseIntervals?.count, 1)
        XCTAssertEqual(workout.elapsedSessionSeconds(
            at: resumed.addingTimeInterval(30)
        ), 80, accuracy: 0.001)

        var watchWorkout = workout
        watchWorkout.captureDevice = .appleWatch
        watchWorkout.recordRecoveredDowntime(
            from: resumed, until: resumed.addingTimeInterval(100)
        )
        XCTAssertEqual(watchWorkout.recoveryPauseIntervals?.count, 1)
        XCTAssertEqual(watchWorkout.excludedRecoverySeconds ?? 0, 350, accuracy: 0.001)
    }

    func testSharedStrengthEffortClockExcludesOnlyExplicitPause() {
        let clock = StrengthSetEffortClock(
            workoutID: UUID(),
            exerciseID: UUID(),
            setID: UUID(),
            startedAt: start,
            pausedAt: start.addingTimeInterval(40),
            totalPausedSeconds: 10
        )
        XCTAssertEqual(clock.elapsedSeconds(at: start.addingTimeInterval(100)),
                       30, accuracy: 0.001)
        XCTAssertEqual(ATHLTHWorkoutSessionClock.elapsed(
            startedAt: start, pausedAt: nil,
            excludedPauseSeconds: 10,
            at: start.addingTimeInterval(100)
        ), 90, accuracy: 0.001)
    }

    func testCountdownRetainsOvertimeAndDoesNotDependOnForegroundTicks() {
        XCTAssertEqual(ATHLTHWorkoutSessionClock.remaining(
            secondsAtPause: 300,
            resumedAt: start,
            at: start.addingTimeInterval(340)
        ), -40, accuracy: 0.001)
        XCTAssertEqual(ATHLTHWorkoutSessionClock.remaining(
            secondsAtPause: -40,
            resumedAt: nil,
            at: start.addingTimeInterval(900)
        ), -40, accuracy: 0.001)
    }

    func testRecoveredIPhoneStrengthTimersFreezeAtDurableCheckpoint() {
        let workoutID = UUID()
        let exerciseID = UUID()
        let setID = UUID()
        let checkpoint = start.addingTimeInterval(45)
        let reopened = start.addingTimeInterval(3600)

        var countdown = StrengthTimedSetCountdown(
            workoutID: workoutID, exerciseID: exerciseID, setID: setID,
            targetSeconds: 120, secondsAtPause: 120, resumedAt: start
        )
        countdown.pause(at: checkpoint)
        XCTAssertFalse(countdown.isRunning)
        XCTAssertEqual(countdown.remaining(at: reopened), 75, accuracy: 0.001)
        countdown.resumedAt = reopened
        XCTAssertEqual(countdown.remaining(
            at: reopened.addingTimeInterval(10)
        ), 65, accuracy: 0.001)

        var effort = StrengthSetEffortClock(
            workoutID: workoutID, exerciseID: exerciseID,
            setID: setID, startedAt: start
        )
        effort.pause(at: checkpoint)
        XCTAssertEqual(effort.elapsedSeconds(at: reopened), 45, accuracy: 0.001)
        effort.resume(at: reopened)
        XCTAssertEqual(effort.elapsedSeconds(
            at: reopened.addingTimeInterval(10)
        ), 55, accuracy: 0.001)
    }

    func testRecoveredTimedSetPreservesOvertimeWithoutAddingOfflineTime() {
        let id = UUID()
        let checkpoint = start.addingTimeInterval(35)
        let reopened = start.addingTimeInterval(3600)
        var countdown = StrengthTimedSetCountdown(
            workoutID: id, exerciseID: UUID(), setID: UUID(),
            targetSeconds: 20, secondsAtPause: 20, resumedAt: start
        )
        countdown.pause(at: checkpoint)
        XCTAssertEqual(countdown.overtimeSeconds(at: reopened), 15)
        countdown.pause(at: reopened)
        XCTAssertEqual(countdown.overtimeSeconds(at: reopened), 15)
    }

    func testWatchAndIPhoneTimedStrengthClocksStayIdentical() {
        var watch = WatchTimedStrengthCountdown(
            targetSeconds: 300, secondsAtPause: 300, resumedAt: start
        )
        var phone = StrengthTimedSetCountdown(
            workoutID: UUID(), exerciseID: UUID(), setID: UUID(),
            targetSeconds: 300, secondsAtPause: 300, resumedAt: start
        )
        let early = start.addingTimeInterval(125)
        XCTAssertEqual(watch.remaining(at: early),
                       phone.remaining(at: early), accuracy: 0.001)
        XCTAssertEqual(watch.elapsed(at: early),
                       Double(phone.elapsedSeconds(at: early)), accuracy: 0.001)

        // After the phone locks, Watch and phone preserve the same remaining
        // seconds from the checkpoint, without a foreground timer.
        watch.secondsAtPause = watch.remaining(at: early)
        phone.secondsAtPause = phone.remaining(at: early)
        watch.resumedAt = nil
        phone.resumedAt = nil
        XCTAssertEqual(watch.remaining(at: start.addingTimeInterval(500)),
                       phone.remaining(at: start.addingTimeInterval(500)),
                       accuracy: 0.001)

        watch.resumedAt = start.addingTimeInterval(500)
        phone.resumedAt = start.addingTimeInterval(500)
        let late = start.addingTimeInterval(725)
        XCTAssertEqual(watch.remaining(at: late),
                       phone.remaining(at: late), accuracy: 0.001)
        XCTAssertEqual(watch.elapsed(at: late),
                       Double(phone.elapsedSeconds(at: late)), accuracy: 0.001)
    }

    func testRunningSessionProjectionUsesOriginalIdentity() {
        var workout = phone(walking: true)
        let sourceID = UUID()
        workout.plannedSessionID = sourceID
        let context = ATHLTHWorkoutSessionFoundation.running(
            workout, at: start.addingTimeInterval(30)
        )
        XCTAssertEqual(context.workoutID, workout.id)
        XCTAssertEqual(context.plannedSessionID, sourceID)
        XCTAssertEqual(context.recordingOwner, .iPhone)
        XCTAssertEqual(context.activity, .walking)
        XCTAssertEqual(context.engine, .endurance)
        XCTAssertEqual(context.phase, .work)
        XCTAssertEqual(context.activeElapsedSeconds, 30, accuracy: 0.001)
        XCTAssertNil(context.stageIndex)
        XCTAssertNil(context.stageCount)
    }

    func testPausedRunningIsNotRecoveryAndDoesNotMoveClock() {
        var workout = phone()
        workout.accumulatedSeconds = 125
        workout.resumedAt = nil
        let context = ATHLTHWorkoutSessionFoundation.running(
            workout, at: start.addingTimeInterval(1000)
        )
        XCTAssertEqual(context.phase, .paused)
        XCTAssertEqual(context.activeElapsedSeconds, 125, accuracy: 0.001)
        XCTAssertEqual(context.workoutID, workout.id)
    }

    func testPhaseChangesCannotChangeRecordingIdentity() {
        let id = UUID()
        XCTAssertTrue(ATHLTHWorkoutSessionFoundation.preservesWorkoutID(id, id))
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.preservesWorkoutID(id, UUID()))
    }

    func testActivityTransitionCannotSilentlyTransferRecordingOwner() {
        let id = UUID()
        let original = ATHLTHWorkoutSessionState(
            workoutID: id, plannedSessionID: nil,
            recordingOwner: .appleWatch, activity: .strength,
            phase: .work, engine: .strength, startedAt: start,
            activeElapsedSeconds: 30, stageIndex: 0, stageCount: 2
        )
        let changedActivity = ATHLTHWorkoutSessionState(
            workoutID: id, plannedSessionID: nil,
            recordingOwner: .appleWatch, activity: .running,
            phase: .work, engine: .endurance, startedAt: start,
            activeElapsedSeconds: 40, stageIndex: 1, stageCount: 2
        )
        let changedOwner = ATHLTHWorkoutSessionState(
            workoutID: id, plannedSessionID: nil,
            recordingOwner: .iPhone, activity: .running,
            phase: .work, engine: .endurance, startedAt: start,
            activeElapsedSeconds: 40, stageIndex: 1, stageCount: 2
        )
        XCTAssertTrue(ATHLTHWorkoutSessionFoundation.preservesRecordingOwnership(
            original, changedActivity
        ))
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.preservesRecordingOwnership(
            original, changedOwner
        ))
    }

    func testUniversalSessionArbitrationRejectsParallelRecordings() throws {
        let id = UUID()
        func state(_ workoutID: UUID, _ owner: ATHLTHWorkoutRecordingOwner)
            -> ATHLTHWorkoutSessionState {
            ATHLTHWorkoutSessionState(
                workoutID: workoutID, plannedSessionID: nil,
                recordingOwner: owner, activity: .strength,
                phase: .work, engine: .strength, startedAt: start,
                activeElapsedSeconds: 10, stageIndex: nil, stageCount: nil
            )
        }
        let first = state(id, .appleWatch)
        XCTAssertNil(try ATHLTHWorkoutSessionFoundation.uniqueActiveSession(
            running: nil, strength: nil
        ))
        XCTAssertEqual(try ATHLTHWorkoutSessionFoundation.uniqueActiveSession(
            running: first, strength: nil
        )?.workoutID, id)
        XCTAssertEqual(try ATHLTHWorkoutSessionFoundation.uniqueActiveSession(
            running: first, strength: state(id, .appleWatch)
        )?.workoutID, id)
        XCTAssertThrowsError(try ATHLTHWorkoutSessionFoundation.uniqueActiveSession(
            running: first, strength: state(UUID(), .appleWatch)
        ))
        XCTAssertThrowsError(try ATHLTHWorkoutSessionFoundation.uniqueActiveSession(
            running: first, strength: state(id, .iPhone)
        ))
    }

    func testRecoveryRejectsCommittedWorkoutEvenWhenCheckpointIsActive() {
        let workout = phone()
        let active = ATHLTHWorkoutSessionFoundation.running(workout, at: start)
        XCTAssertNotNil(ATHLTHWorkoutSessionFoundation.recoverableSession(
            active, alreadyCommittedWorkoutIDs: []
        ))
        XCTAssertNil(ATHLTHWorkoutSessionFoundation.recoverableSession(
            active, alreadyCommittedWorkoutIDs: [workout.id]
        ))
    }

    func testLateDeviceSnapshotCannotChangeRecordingOwnershipOrIdentity() {
        let workout = phone()
        let current = ATHLTHWorkoutSessionFoundation.running(workout, at: start)
        let other = ATHLTHWorkoutSessionState(
            workoutID: UUID(), plannedSessionID: nil,
            recordingOwner: .iPhone, activity: .running,
            phase: .work, engine: .endurance, startedAt: start,
            activeElapsedSeconds: 30, stageIndex: nil, stageCount: nil
        )
        XCTAssertTrue(ATHLTHWorkoutSessionFoundation.acceptsDeviceSnapshot(
            current: current, incoming: current
        ))
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.acceptsDeviceSnapshot(
            current: current, incoming: other
        ))
    }

    func testSharedRecordingRejectsConflictingPlanAndStartMetadata() throws {
        let id = UUID()
        func snapshot(_ plan: UUID?, _ started: Date) -> ATHLTHWorkoutSessionState {
            ATHLTHWorkoutSessionState(
                workoutID: id, plannedSessionID: plan,
                recordingOwner: .appleWatch, activity: .strength,
                phase: .work, engine: .strength, startedAt: started,
                activeElapsedSeconds: 20, stageIndex: nil, stageCount: nil
            )
        }
        let plan = UUID()
        let original = snapshot(plan, start)
        XCTAssertEqual(try ATHLTHWorkoutSessionFoundation.uniqueActiveSession(
            running: original, strength: snapshot(plan, start)
        )?.workoutID, id)
        XCTAssertThrowsError(try ATHLTHWorkoutSessionFoundation.uniqueActiveSession(
            running: original, strength: snapshot(UUID(), start)
        ))
        XCTAssertThrowsError(try ATHLTHWorkoutSessionFoundation.uniqueActiveSession(
            running: original, strength: snapshot(plan, start.addingTimeInterval(1))
        ))
    }

    func testOfflineProgressCannotRewindOrDuplicateCompletion() {
        let base = ATHLTHWorkoutSessionState(
            workoutID: UUID(), plannedSessionID: nil,
            recordingOwner: .appleWatch, activity: .strength,
            phase: .work, engine: .strength, startedAt: start,
            activeElapsedSeconds: 120, stageIndex: nil, stageCount: nil
        )
        func update(_ elapsed: TimeInterval) -> ATHLTHWorkoutSessionState {
            ATHLTHWorkoutSessionState(
                workoutID: base.workoutID, plannedSessionID: nil,
                recordingOwner: .appleWatch, activity: .running,
                phase: .work, engine: .endurance, startedAt: start,
                activeElapsedSeconds: elapsed, stageIndex: nil, stageCount: nil
            )
        }
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.acceptsProgressUpdate(
            current: base, incoming: update(119)
        ))
        XCTAssertTrue(ATHLTHWorkoutSessionFoundation.acceptsProgressUpdate(
            current: base, incoming: update(121)
        ))
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.acceptsProgressUpdate(
            current: base, incoming: update(.nan)
        ))
        XCTAssertTrue(ATHLTHWorkoutSessionFoundation.shouldCommitCompletion(
            workoutID: base.workoutID, committedWorkoutIDs: []
        ))
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.shouldCommitCompletion(
            workoutID: base.workoutID, committedWorkoutIDs: [base.workoutID]
        ))
    }

    func testCompletionTimeUsesActualFinishNotRecoveredCheckpoint() {
        let checkpoint = start.addingTimeInterval(90)
        let athleteFinishedAt = start.addingTimeInterval(360)
        XCTAssertEqual(ATHLTHWorkoutSessionFoundation.completionTimestamp(
            startedAt: start,
            finishedAt: athleteFinishedAt
        ), athleteFinishedAt)
        XCTAssertNotEqual(checkpoint, athleteFinishedAt)
        // Clock rollback cannot generate a negative-length workout.
        XCTAssertEqual(ATHLTHWorkoutSessionFoundation.completionTimestamp(
            startedAt: start,
            finishedAt: start.addingTimeInterval(-10)
        ), start)
    }

    func testRecoveryNeverResurrectsCompletedHistory() {
        XCTAssertTrue(ATHLTHWorkoutSessionFoundation.mayRecoverCheckpoint(
            hasEnded: false, alreadyCommitted: false
        ))
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.mayRecoverCheckpoint(
            hasEnded: true, alreadyCommitted: false
        ))
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.mayRecoverCheckpoint(
            hasEnded: false, alreadyCommitted: true
        ))
    }

    func testSecondLaunchIsRejectedWithoutDiscardingFirst() {
        let workout = phone()
        let live = ATHLTHWorkoutSessionFoundation.running(workout, at: start)
        XCTAssertNoThrow(try ATHLTHWorkoutSessionFoundation.requireNoActiveRecording(nil))
        XCTAssertThrowsError(
            try ATHLTHWorkoutSessionFoundation.requireNoActiveRecording(live)
        )
    }

    @MainActor
    func testLaunchReservationSerializesRunWalkAndStrengthPreflights() throws {
        // Both existing authoritative stores are registered when constructed.
        // No HealthKit session or user history is created by a reservation.
        let phone = IPhoneWorkoutStore()
        let strength = StrengthWorkoutStore()
        XCTAssertNil(phone.active)
        XCTAssertNil(strength.activeWorkout)

        let first = try ATHLTHWorkoutRecordingArbiter.reserveLaunch()
        XCTAssertThrowsError(try ATHLTHWorkoutRecordingArbiter.reserveLaunch())
        ATHLTHWorkoutRecordingArbiter.releaseLaunch(UUID())
        XCTAssertThrowsError(try ATHLTHWorkoutRecordingArbiter.reserveLaunch())

        ATHLTHWorkoutRecordingArbiter.releaseLaunch(first)
        let next = try ATHLTHWorkoutRecordingArbiter.reserveLaunch()
        ATHLTHWorkoutRecordingArbiter.releaseLaunch(first)
        XCTAssertThrowsError(try ATHLTHWorkoutRecordingArbiter.reserveLaunch())
        ATHLTHWorkoutRecordingArbiter.releaseLaunch(next)

        strength.startFreestyle(watchSessionID: nil)
        XCTAssertNotNil(strength.activeWorkout)
        XCTAssertThrowsError(try ATHLTHWorkoutRecordingArbiter.reserveLaunch())
    }

    @MainActor
    func testWatchMirrorBlocksSecondRecordingButAllowsMatchingWatchStrengthRestore() throws {
        let strength = StrengthWorkoutStore()
        strength.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        let bootstrap = try XCTUnwrap(strength.watchSnapshot)
        let startedAt = try XCTUnwrap(bootstrap.startedAt)
        var mirror = WatchWorkoutLiveSnapshot(
            kind: .strength, state: .running,
            startedAt: startedAt,
            capturedAt: startedAt.addingTimeInterval(1),
            elapsedTime: 1, heartRate: 110, activeCalories: 1,
            distanceMeters: 0, averageHeartRate: nil,
            maxHeartRate: nil, routePointCount: 0
        )
        mirror.strengthWorkoutID = bootstrap.workoutID
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.isRecordingSlotAvailable(
            running: nil, runningAuthorizationPending: false, strength: nil,
            mirroredWatchRecordingActive: true
        ))
        XCTAssertTrue(ATHLTHWorkoutSessionFoundation.canBootstrapWatchStrength(
            mirror: mirror, mirrorActive: true, bootstrap: bootstrap
        ))
        mirror.state = .completed
        XCTAssertTrue(ATHLTHWorkoutSessionFoundation.canBootstrapWatchStrength(
            mirror: mirror, mirrorActive: true, bootstrap: bootstrap
        ), "A completed Watch session can restore its exact matching log before the mirror disconnects")
        mirror.state = .running
        mirror.strengthWorkoutID = UUID()
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.canBootstrapWatchStrength(
            mirror: mirror, mirrorActive: true, bootstrap: bootstrap
        ))
        mirror.strengthWorkoutID = bootstrap.workoutID
        mirror.kind = .running
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.canBootstrapWatchStrength(
            mirror: mirror, mirrorActive: true, bootstrap: bootstrap
        ))
        mirror.kind = .strength
        mirror.startedAt = startedAt.addingTimeInterval(45)
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.canBootstrapWatchStrength(
            mirror: mirror, mirrorActive: true, bootstrap: bootstrap
        ))
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.canBootstrapWatchStrength(
            mirror: nil, mirrorActive: true, bootstrap: bootstrap
        ))
        XCTAssertTrue(ATHLTHWorkoutSessionFoundation.canBootstrapWatchStrength(
            mirror: nil, mirrorActive: false, bootstrap: bootstrap
        ))
    }

    func testPendingOutdoorPermissionBlocksUniversalRecordingSlot() {
        let live = ATHLTHWorkoutSessionFoundation.running(phone(), at: start)
        XCTAssertTrue(ATHLTHWorkoutSessionFoundation.isRecordingSlotAvailable(
            running: nil, runningAuthorizationPending: false, strength: nil
        ))
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.isRecordingSlotAvailable(
            running: nil, runningAuthorizationPending: true, strength: nil
        ))
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.isRecordingSlotAvailable(
            running: live, runningAuthorizationPending: false, strength: nil
        ))
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.isRecordingSlotAvailable(
            running: nil, runningAuthorizationPending: false, strength: live
        ))
    }

    @MainActor
    func testCurrentSessionReadsActualStrengthStoreWithoutCreatingRecording() throws {
        let phone = IPhoneWorkoutStore()
        let strength = StrengthWorkoutStore()
        XCTAssertNil(try ATHLTHWorkoutSessionFoundation.currentSession(
            phone: phone, strength: strength
        ))
        strength.startFreestyle(watchSessionID: nil)
        let originalID = try XCTUnwrap(strength.activeWorkout?.id)
        XCTAssertEqual(try ATHLTHWorkoutSessionFoundation.currentSession(
            phone: phone, strength: strength
        )?.workoutID, originalID)
        XCTAssertThrowsError(try ATHLTHWorkoutSessionFoundation.requireAvailableRecordingSlot(
            phone: phone, strength: strength
        ))
        XCTAssertEqual(strength.activeWorkout?.id, originalID)
    }

    @MainActor
    func testStrengthProjectionKeepsWatchOwnershipThroughInternalRest() throws {
        let store = StrengthWorkoutStore()
        let plan = PlannedSession(
            id: UUID(),
            title: "Strength",
            kind: .strength,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: ""
        )
        store.start(
            session: plan,
            watchSessionID: UUID(),
            trackingMode: .advanced,
            captureDevice: .appleWatch
        )
        let workout = try XCTUnwrap(store.activeWorkout)
        let context = try XCTUnwrap(store.activeSessionState)
        XCTAssertEqual(context.workoutID, workout.id)
        XCTAssertEqual(context.plannedSessionID, plan.id)
        XCTAssertEqual(context.recordingOwner, .appleWatch)
        XCTAssertEqual(context.phase, .work)
        XCTAssertEqual(context.engine, .strength)
        let resting = ATHLTHWorkoutSessionFoundation.strength(
            workout, exerciseIndex: 0, isResting: true,
            at: workout.startedAt.addingTimeInterval(90)
        )
        XCTAssertEqual(resting.phase, .recovery)
        XCTAssertEqual(resting.engine, .recovery)
        XCTAssertEqual(resting.workoutID, context.workoutID)
        XCTAssertEqual(resting.activeElapsedSeconds, 90, accuracy: 0.001)
    }

    @MainActor
    func testStartingAnotherStrengthWorkoutCannotOverwriteActiveCheckpoint() {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        let firstID = store.activeWorkout?.id
        XCTAssertNotNil(firstID)

        store.startFreestyle(watchSessionID: UUID())
        XCTAssertEqual(store.activeWorkout?.id, firstID)
        XCTAssertEqual(store.activeWorkout?.captureDevice, .iPhone)

        let other = PlannedSession(
            id: UUID(), title: "Another",
            kind: .strength, scheduledStart: nil,
            durationMinutes: nil, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: ""
        )
        store.start(
            session: other,
            watchSessionID: nil,
            trackingMode: .simple,
            captureDevice: .iPhone
        )
        XCTAssertEqual(store.activeWorkout?.id, firstID)
        XCTAssertNil(store.activeWorkout?.plannedSessionID)
    }

    @MainActor
    func testLongStrengthWorkoutRecoveryDoesNotCountLockedPhoneDowntime() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        var workout = try XCTUnwrap(store.activeWorkout)
        let start = workout.startedAt
        let checkpoint = start.addingTimeInterval(3_600)
        let unlocked = start.addingTimeInterval(11 * 3_600)
        let finished = start.addingTimeInterval(12 * 3_600)

        XCTAssertEqual(workout.elapsedSessionSeconds(
            at: finished, suspendedAt: checkpoint
        ), 3_600, accuracy: 0.001)
        workout.recordRecoveredDowntime(from: checkpoint, until: unlocked)
        workout.endedAt = finished
        XCTAssertEqual(workout.excludedRecoverySeconds ?? 0, 36_000)
        XCTAssertEqual(workout.elapsedSessionSeconds(at: finished), 7_200)
        let result = StrengthWorkoutResultBreakdown(
            workout: workout, elapsedSeconds: workout.elapsedSessionSeconds(
                at: finished
            )
        )
        XCTAssertEqual(result.totalSeconds, 7_200)
        XCTAssertEqual(result.restSeconds, 0)
        XCTAssertEqual(result.activeSeconds, 7_200)
        // A second recovery of the same checkpoint cannot add hours twice.
        workout.recordRecoveredDowntime(from: checkpoint, until: unlocked)
        XCTAssertEqual(workout.elapsedSessionSeconds(at: finished), 7_200)
    }

    func testWholeWorkoutClockSurvivesMultipleHoursAndExplicitPause() {
        let started = Date(timeIntervalSince1970: 1_900_000_000)
        let pausedAt = started.addingTimeInterval(4 * 3_600)
        let later = pausedAt.addingTimeInterval(16 * 3_600)
        XCTAssertEqual(
            ATHLTHWorkoutSessionClock.elapsed(
                startedAt: started, pausedAt: pausedAt,
                excludedPauseSeconds: 60 * 15, at: later
            ),
            13_500
        )
        XCTAssertEqual(
            ATHLTHWorkoutSessionClock.elapsed(
                activeBeforeResume: 13_500, resumedAt: nil, at: later
            ),
            13_500
        )
        XCTAssertEqual(
            ATHLTHWorkoutSessionClock.elapsed(
                activeBeforeResume: 13_500, resumedAt: later,
                at: later.addingTimeInterval(90)
            ),
            13_590
        )
    }

    @MainActor
    func testPlannedStrengthStartOnlyConfirmsExactWatchOwnerAndSession() throws {
        let store = StrengthWorkoutStore()
        let planned = PlannedSession(
            id: UUID(), title: "Strength",
            kind: .strength, scheduledStart: nil,
            durationMinutes: nil, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: ""
        )
        let watchID = UUID()
        XCTAssertFalse(store.matchesStartedPlannedWorkout(
            sessionID: planned.id, captureDevice: .appleWatch,
            watchSessionID: watchID
        ))
        store.start(
            session: planned, watchSessionID: watchID,
            trackingMode: .advanced, captureDevice: .appleWatch
        )
        XCTAssertTrue(store.matchesStartedPlannedWorkout(
            sessionID: planned.id, captureDevice: .appleWatch,
            watchSessionID: watchID
        ))
        XCTAssertFalse(store.matchesStartedPlannedWorkout(
            sessionID: UUID(), captureDevice: .appleWatch,
            watchSessionID: watchID
        ))
        XCTAssertFalse(store.matchesStartedPlannedWorkout(
            sessionID: planned.id, captureDevice: .iPhone,
            watchSessionID: watchID
        ))
        XCTAssertFalse(store.matchesStartedPlannedWorkout(
            sessionID: planned.id, captureDevice: .appleWatch,
            watchSessionID: UUID()
        ))

        let competing = PlannedSession(
            id: UUID(), title: "Competing workout",
            kind: .strength, scheduledStart: nil,
            durationMinutes: nil, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: ""
        )
        store.start(
            session: competing, watchSessionID: UUID(),
            trackingMode: .simple, captureDevice: .appleWatch
        )
        XCTAssertTrue(store.matchesStartedPlannedWorkout(
            sessionID: planned.id, captureDevice: .appleWatch,
            watchSessionID: watchID
        ), "A rejected second launch cannot claim the first recording")
        XCTAssertFalse(store.matchesStartedPlannedWorkout(
            sessionID: competing.id, captureDevice: .appleWatch,
            watchSessionID: watchID
        ))
    }

    @MainActor
    func testIPhoneStrengthStartRequiresMatchingCheckpointBeforeCalendarAdvance() {
        let store = StrengthWorkoutStore()
        let planned = PlannedSession(
            id: UUID(), title: "Strength",
            kind: .strength, scheduledStart: nil,
            durationMinutes: nil, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: ""
        )
        store.start(
            session: planned, watchSessionID: nil,
            trackingMode: .simple, captureDevice: .iPhone
        )
        XCTAssertTrue(store.matchesStartedPlannedWorkout(
            sessionID: planned.id, captureDevice: .iPhone,
            watchSessionID: nil
        ))
        XCTAssertFalse(store.matchesStartedPlannedWorkout(
            sessionID: planned.id, captureDevice: .appleWatch,
            watchSessionID: nil
        ))
        XCTAssertFalse(store.matchesStartedPlannedWorkout(
            sessionID: planned.id, captureDevice: .iPhone,
            watchSessionID: UUID()
        ))
    }
    func testActiveWatchBeforeMirroringOccupiesSingleSlot() {
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.isRecordingSlotAvailable(
            running: nil, runningAuthorizationPending: false, strength: nil,
            remoteWatchRecordingActive: true
        ))
        XCTAssertFalse(ATHLTHWorkoutSessionFoundation.isRecordingSlotAvailable(
            running: nil, runningAuthorizationPending: false, strength: nil,
            mirroredWatchRecordingActive: true
        ))
        XCTAssertTrue(ATHLTHWorkoutSessionFoundation.isRecordingSlotAvailable(
            running: nil, runningAuthorizationPending: false, strength: nil
        ))
    }

    @MainActor
    func testArbiterRegistersOriginalWatchConnectionWithoutExtraRecording() {
        let connection = AppleWatchConnectionStore()
        XCTAssertTrue(ATHLTHWorkoutRecordingArbiter.watchConnection === connection)
    }


    func testUnifiedSlotRejectsWatchBeforeMirrorAndPendingPreflights() {
        func available(
            phone: Bool = false,
            manual: Bool = false,
            structured: Bool = false,
            mirror: Bool = false,
            watch: Bool = false
        ) -> Bool {
            ATHLTHWorkoutSessionFoundation.canStartNewRecorder(
                phonePending: phone, manualActive: manual,
                structuredActive: structured,
                mirroredWatchActive: mirror,
                unmirroredWatchActive: watch
            )
        }
        XCTAssertTrue(available())
        XCTAssertFalse(available(phone: true))
        XCTAssertFalse(available(manual: true))
        XCTAssertFalse(available(structured: true))
        XCTAssertFalse(available(mirror: true))
        XCTAssertFalse(available(watch: true))
        XCTAssertFalse(available(mirror: true, watch: true))
        XCTAssertFalse(available(manual: true, watch: true))
    }


    func testOriginalRecordingLogsOwnTheSlotEvenWithoutLiveProjection() {
        XCTAssertTrue(ATHLTHWorkoutSessionFoundation.originalRecordersIdle(
            phoneWorkoutExists: false, strengthWorkoutExists: false
        ))
        for (phone, strength) in [
            (true, false), (false, true), (true, true)
        ] {
            XCTAssertFalse(ATHLTHWorkoutSessionFoundation.originalRecordersIdle(
                phoneWorkoutExists: phone,
                strengthWorkoutExists: strength
            ))
        }
        // A stored PhoneWorkout/StrengthWorkoutLog must never be replaced
        // simply because the derived UI projection is temporarily nil.
    }

    @MainActor
    func testOriginalStrengthLogPreventsEverySecondLaunchPath() throws {
        let phone = IPhoneWorkoutStore()
        let strength = StrengthWorkoutStore()
        strength.startFreestyle(watchSessionID: nil)
        XCTAssertNotNil(strength.activeWorkout)
        XCTAssertFalse(ATHLTHWorkoutRecordingArbiter.mayStartRunning())
        XCTAssertFalse(ATHLTHWorkoutRecordingArbiter.mayStartStrength())
        XCTAssertThrowsError(try ATHLTHWorkoutRecordingArbiter.reserveLaunch())
        XCTAssertThrowsError(try ATHLTHWorkoutSessionFoundation
            .requireAvailableRecordingSlot(phone: phone, strength: strength))
    }

}
