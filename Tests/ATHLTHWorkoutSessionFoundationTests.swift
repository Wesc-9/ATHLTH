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
}
