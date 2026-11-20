import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHUniversalActiveCaptureTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 1_900_000_000)

    private func timer(
        activity: CustomQuickWorkoutActivity = .cycling,
        method: CustomQuickWorkoutMethod = .open,
        accumulatedSeconds: TimeInterval = 0,
        resumedAt: Date? = nil
    ) -> ATHLTHManualTimedCheckpoint {
        ATHLTHManualTimedCheckpoint(
            id: UUID(), userID: UUID(), activity: activity, method: method,
            startedAt: started, durationMinutes: 30,
            workSeconds: 40, restSeconds: 20, rounds: 3,
            titleOverride: nil, accumulatedSeconds: accumulatedSeconds,
            resumedAt: resumedAt, approvedTimeLimit: 18_000
        )
    }

    private func block(
        kind: WorkoutTemplateBlockKind, sequence: Int
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: sequence, kind: kind, title: "Step",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 300, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )
    }

    func testAllCustomActivitiesKeepOriginalIDAndManualEvidence() throws {
        for kind in CustomQuickWorkoutActivity.allCases {
            let original = timer(activity: kind, resumedAt: started)
            let active = try XCTUnwrap(
                ATHLTHUniversalActiveCapture.manual(
                    original, at: started.addingTimeInterval(70)
                )
            )
            XCTAssertEqual(active.workoutID, original.id)
            XCTAssertEqual(active.activityCategory, kind.rawValue)
            XCTAssertEqual(active.source, .manualTimer)
            XCTAssertTrue(active.source.isManualTiming)
            XCTAssertEqual(active.recordingOwner, .iPhone)
            XCTAssertNil(active.plannedSessionID)
            XCTAssertEqual(active.elapsedSeconds, 70)
            XCTAssertEqual(active.phase, .work)
            let unique = try XCTUnwrap(
                ATHLTHUniversalActiveCapture.unique(
                    running: nil, strength: nil,
                    manual: original, structured: nil,
                    at: started.addingTimeInterval(70)
                )
            )
            XCTAssertEqual(unique, active)
        }
    }

    func testManualIntervalsUseOriginalRoundAndPauseClock() throws {
        let original = timer(method: .intervals, resumedAt: started)
        let rest = try XCTUnwrap(ATHLTHUniversalActiveCapture.manual(
            original, at: started.addingTimeInterval(45)
        ))
        XCTAssertEqual(rest.engine, .recovery)
        XCTAssertEqual(rest.phase, .recovery)
        XCTAssertEqual(rest.stageIndex, 1)
        XCTAssertEqual(rest.stageCount, 5)

        let work = try XCTUnwrap(ATHLTHUniversalActiveCapture.manual(
            original, at: started.addingTimeInterval(75)
        ))
        XCTAssertEqual(work.engine, .cycling)
        XCTAssertEqual(work.phase, .work)
        XCTAssertEqual(work.stageIndex, 2)

        let paused = timer(method: .intervals, accumulatedSeconds: 45)
        let frozen = try XCTUnwrap(ATHLTHUniversalActiveCapture.manual(
            paused, at: started.addingTimeInterval(900)
        ))
        XCTAssertEqual(frozen.phase, .paused)
        XCTAssertEqual(frozen.elapsedSeconds, 45)
        XCTAssertEqual(frozen.stageIndex, 1)
    }

    func testStructuredWorkoutKeepsOneIDAcrossDifferentLiveEngines() throws {
        let run = block(kind: .run, sequence: 1)
        var cycle = block(kind: .note, sequence: 2)
        cycle.activityTag = "cycling"
        let id = UUID()
        let saved = ATHLTHStructuredWorkoutCheckpoint(
            workoutID: id, savedAt: started,
            startedAt: started, stepEnteredAt: started,
            currentIndex: 1, completedIDs: [], results: [:],
            modeStarts: [:], executionBlocks: [run, cycle],
            emomWaiting: false, timedOutGroups: [],
            enteredReps: 0, enteredWeight: ""
        )
        let state = try XCTUnwrap(
            ATHLTHUniversalActiveCapture.structured(
                saved, at: started.addingTimeInterval(360)
            )
        )
        XCTAssertEqual(state.workoutID, id)
        XCTAssertEqual(state.source, .structuredTimer)
        XCTAssertEqual(state.activityCategory, "cycling")
        XCTAssertEqual(state.engine, .cycling)
        XCTAssertEqual(state.stageIndex, 1)
        XCTAssertEqual(state.stageCount, 2)
        XCTAssertNil(state.plannedSessionID)
        let unique = try XCTUnwrap(ATHLTHUniversalActiveCapture.unique(
            running: nil, strength: nil,
            manual: nil, structured: saved,
            at: started.addingTimeInterval(360)
        ))
        XCTAssertEqual(unique, state)
    }

    func testUniversalCaptureRejectsParallelOwnersAndPreservesRecordedSource() throws {
        let running = ATHLTHWorkoutSessionFoundation.running(
            PhoneWorkout(
                walking: false, start: started,
                resumedAt: started, lastCheckpoint: started
            ), at: started.addingTimeInterval(60)
        )
        let bike = timer(resumedAt: started)
        XCTAssertThrowsError(try ATHLTHUniversalActiveCapture.unique(
            running: running, strength: nil,
            manual: bike, structured: nil
        ))
        let single = try XCTUnwrap(ATHLTHUniversalActiveCapture.unique(
            running: running, strength: nil,
            manual: nil, structured: nil
        ))
        XCTAssertEqual(single.workoutID, running.workoutID)
        XCTAssertEqual(single.source, .phoneRunWalk)
        XCTAssertFalse(single.source.isManualTiming)
    }

    func testRecordedRunningStrengthHybridAndRecoveryUseActualActiveSport() {
        let workoutID = UUID()
        let plannedID = UUID()
        func original(
            activity: ATHLTHWorkoutSessionActivity,
            phase: ATHLTHWorkoutSessionPhase,
            engine: ATHLTHLiveWorkoutEngine
        ) -> ATHLTHWorkoutSessionState {
            ATHLTHWorkoutSessionState(
                workoutID: workoutID, plannedSessionID: plannedID,
                recordingOwner: .iPhone,
                activity: activity, phase: phase, engine: engine,
                startedAt: started, activeElapsedSeconds: 175,
                stageIndex: 2, stageCount: 6
            )
        }
        let expected: [(ATHLTHWorkoutSessionState, String)] = [
            (original(activity: .running, phase: .work, engine: .endurance),
             "running"),
            (original(activity: .walking, phase: .work, engine: .endurance),
             "walking"),
            (original(activity: .strength, phase: .work, engine: .strength),
             "strength"),
            (original(activity: .strength, phase: .work, engine: .endurance),
             "running"),
            (original(activity: .strength, phase: .paused, engine: .endurance),
             "running"),
            (original(activity: .strength, phase: .recovery, engine: .recovery),
             "recovery"),
            (original(activity: .running, phase: .recovery, engine: .recovery),
             "recovery")
        ]
        for (state, category) in expected {
            let projected = ATHLTHUniversalActiveCapture.recorded(
                state, source: state.activity == .strength
                    ? .strength : .phoneRunWalk
            )
            XCTAssertEqual(projected.activityCategory, category)
            XCTAssertEqual(projected.engine, state.engine)
            XCTAssertEqual(projected.phase, state.phase)
            XCTAssertEqual(projected.workoutID, workoutID)
            XCTAssertEqual(projected.plannedSessionID, plannedID)
            XCTAssertEqual(projected.recordingOwner, .iPhone)
            XCTAssertEqual(projected.elapsedSeconds, 175)
            XCTAssertEqual(projected.stageIndex, 2)
            XCTAssertEqual(projected.stageCount, 6)
        }
    }

    func testMalformedStructuredCursorAndManualTimerNeverBecomeLiveState() {
        var corrupt = timer(resumedAt: started)
        corrupt.accumulatedSeconds = -.infinity
        XCTAssertNil(ATHLTHUniversalActiveCapture.manual(
            corrupt, at: started
        ))
        let saved = ATHLTHStructuredWorkoutCheckpoint(
            workoutID: UUID(), savedAt: started,
            startedAt: started, stepEnteredAt: started,
            currentIndex: 5, completedIDs: [], results: [:],
            modeStarts: [:], executionBlocks: [block(kind: .note, sequence: 1)],
            emomWaiting: false, timedOutGroups: [],
            enteredReps: 0, enteredWeight: ""
        )
        XCTAssertNil(ATHLTHUniversalActiveCapture.structured(
            saved, at: started
        ))
        XCTAssertThrowsError(try ATHLTHUniversalActiveCapture.unique(
            running: nil, strength: nil,
            manual: corrupt, structured: saved
        ))
    }

    func testSameOriginalHybridUsesOneStrengthStageCursor() throws {
        let id = UUID(), planned = UUID()
        let running = ATHLTHWorkoutSessionState(
            workoutID: id, plannedSessionID: planned,
            recordingOwner: .iPhone, activity: .running,
            phase: .work, engine: .endurance,
            startedAt: started, activeElapsedSeconds: 250,
            stageIndex: 1, stageCount: 4
        )
        let strength = ATHLTHWorkoutSessionState(
            workoutID: id, plannedSessionID: planned,
            recordingOwner: .iPhone, activity: .strength,
            phase: .work, engine: .strength,
            startedAt: started, activeElapsedSeconds: 250,
            stageIndex: 3, stageCount: 6
        )
        let unified = try XCTUnwrap(
            ATHLTHUniversalActiveCapture.unique(
                running: running, strength: strength,
                manual: nil, structured: nil
            )
        )
        XCTAssertEqual(unified.workoutID, id)
        XCTAssertEqual(unified.source, .strength)
        XCTAssertEqual(unified.engine, .strength)
        XCTAssertEqual(unified.stageIndex, 3)
        XCTAssertEqual(unified.stageCount, 6)
        XCTAssertThrowsError(try ATHLTHUniversalActiveCapture.unique(
            running: running, strength: strength,
            manual: timer(resumedAt: started), structured: nil
        ))
    }

    @MainActor
    func testPendingLaunchNeverLooksLikeFreeUniversalSlot() throws {
        let launchID = try ATHLTHWorkoutRecordingArbiter.reserveLaunch()
        defer { ATHLTHWorkoutRecordingArbiter.releaseLaunch(launchID) }
        XCTAssertTrue(ATHLTHWorkoutRecordingArbiter.hasPendingLaunch)
        XCTAssertThrowsError(try ATHLTHUniversalActiveCapture.current(
            for: UUID()
        ))
    }

    func testStructuredPausePreservesWorkoutIDAndClock() throws {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let note = block(kind: .note, sequence: 1)
        var checkpoint = ATHLTHStructuredWorkoutCheckpoint(
            workoutID: UUID(), savedAt: start, startedAt: start,
            stepEnteredAt: start, currentIndex: 0,
            completedIDs: [], results: [:], modeStarts: [:],
            executionBlocks: [note], emomWaiting: false,
            timedOutGroups: [], enteredReps: 0, enteredWeight: ""
        )
        checkpoint.pausedAt = start.addingTimeInterval(45)
        let paused = try XCTUnwrap(ATHLTHUniversalActiveCapture.structured(
            checkpoint, at: start.addingTimeInterval(900)
        ))
        XCTAssertEqual(paused.elapsedSeconds, 45)
        XCTAssertEqual(paused.phase, .paused)
        checkpoint.pausedAt = nil
        checkpoint.completedPauseSeconds = 855
        let resumed = try XCTUnwrap(ATHLTHUniversalActiveCapture.structured(
            checkpoint, at: start.addingTimeInterval(910)
        ))
        XCTAssertEqual(resumed.elapsedSeconds, 55)
        XCTAssertEqual(resumed.workoutID, paused.workoutID)
    }


    func testManualSpectatorUsesSameIntervalCursorWithoutFabricatedSensors() throws {
        let active = timer(method: .intervals, resumedAt: started)
        let now = started.addingTimeInterval(45)
        let preview = try XCTUnwrap(
            ATHLTHManualSpectatorSnapshot.make(active, at: now)
        )
        let universal = try XCTUnwrap(
            ATHLTHUniversalActiveCapture.manual(active, at: now)
        )
        XCTAssertEqual(preview.sessionID, universal.workoutID)
        XCTAssertEqual(preview.elapsedSeconds, universal.elapsedSeconds)
        XCTAssertEqual(preview.startedAt, universal.startedAt)
        XCTAssertEqual(preview.kind, active.activity.rawValue)
        XCTAssertEqual(preview.sourceDevice, "iphone")
        XCTAssertEqual(preview.paused, false)
        XCTAssertEqual(preview.runningIntervalOrdinal, 2)
        XCTAssertEqual(preview.runningIntervalTotal, 5)
        XCTAssertEqual(preview.runningInRecovery, true)
        XCTAssertEqual(preview.runningStepRemainingSeconds, 15)
        XCTAssertNil(preview.distanceMeters)
        XCTAssertNil(preview.heartRateBPM)
        XCTAssertNil(preview.activeCalories)
        XCTAssertNil(preview.currentPaceSecondsPerKilometer)
        XCTAssertNil(preview.liveLatitude)
        XCTAssertNil(preview.liveLongitude)
        XCTAssertNil(preview.spotifyPlaying)
    }

    func testManualSpectatorFreezesWhenPausedAndRejectsUnreadableTimer() throws {
        let original = timer(method: .tabata, accumulatedSeconds: 23)
        let now = started.addingTimeInterval(1100)
        let preview = try XCTUnwrap(ATHLTHManualSpectatorSnapshot.make(
            original, at: now
        ))
        XCTAssertEqual(preview.paused, true)
        XCTAssertEqual(preview.elapsedSeconds, 23)
        XCTAssertEqual(preview.runningInRecovery, true)
        XCTAssertEqual(preview.runningStepRemainingSeconds, 7)
        XCTAssertEqual(preview.runningIntervalOrdinal, 2)
        XCTAssertNil(preview.distanceMeters)
        var invalid = original
        invalid.approvedTimeLimit = -.infinity
        XCTAssertNil(ATHLTHManualSpectatorSnapshot.make(invalid, at: now))
    }

    func testManualSpectatorCanRepresentEverySavedActivityWithoutSensors() throws {
        for sport in CustomQuickWorkoutActivity.allCases {
            let source = timer(activity: sport, resumedAt: started)
            let preview = try XCTUnwrap(
                ATHLTHManualSpectatorSnapshot.make(
                    source, at: started.addingTimeInterval(90)
                )
            )
            XCTAssertEqual(preview.sessionID, source.id)
            XCTAssertEqual(preview.kind, sport.rawValue)
            XCTAssertNil(preview.distanceMeters)
            XCTAssertNil(preview.heartRateBPM)
            XCTAssertNil(preview.activeCalories)
            XCTAssertNil(preview.liveLatitude)
        }
    }


    func testConflictingCaptureSourcesCannotHideAnotherWorkout() {
        let now = started
        let running = ATHLTHWorkoutSessionState(
            workoutID: UUID(), plannedSessionID: nil,
            recordingOwner: .iPhone, activity: .running,
            phase: .work, engine: .endurance,
            startedAt: now, activeElapsedSeconds: 35,
            stageIndex: nil, stageCount: nil
        )
        let strength = ATHLTHWorkoutSessionState(
            workoutID: UUID(), plannedSessionID: nil,
            recordingOwner: .iPhone, activity: .strength,
            phase: .work, engine: .strength,
            startedAt: now, activeElapsedSeconds: 35,
            stageIndex: nil, stageCount: nil
        )
        func consistent(
            run: ATHLTHWorkoutSessionState? = nil,
            lifting: ATHLTHWorkoutSessionState? = nil,
            manual: Bool = false, structured: Bool = false,
            mirror: Bool = false, watchID: UUID? = nil,
            watchStart: Date? = nil
        ) -> Bool {
            ATHLTHUniversalActiveCapture.sourcesConsistent(
                running: run, strength: lifting,
                manualActive: manual, structuredActive: structured,
                watchMirrorActive: mirror,
                mirrorStrengthWorkoutID: watchID,
                mirrorStartedAt: watchStart
            )
        }
        XCTAssertTrue(consistent(run: running))
        XCTAssertTrue(consistent(manual: true))
        XCTAssertTrue(consistent(structured: true))
        XCTAssertFalse(consistent(run: running, lifting: strength))
        XCTAssertFalse(consistent(run: running, manual: true))
        XCTAssertFalse(consistent(lifting: strength, structured: true))
        XCTAssertFalse(consistent(manual: true, structured: true))
        XCTAssertFalse(consistent(run: running, mirror: true))
        XCTAssertFalse(consistent(manual: true, mirror: true))
        XCTAssertFalse(consistent(lifting: strength, mirror: true))
        let watchStrength = ATHLTHWorkoutSessionState(
            workoutID: strength.workoutID, plannedSessionID: nil,
            recordingOwner: .appleWatch, activity: .strength,
            phase: .work, engine: .strength,
            startedAt: now, activeElapsedSeconds: 35,
            stageIndex: nil, stageCount: nil
        )
        XCTAssertTrue(consistent(
            lifting: watchStrength, mirror: true,
            watchID: watchStrength.workoutID, watchStart: now
        ))
        XCTAssertFalse(consistent(
            lifting: watchStrength, mirror: true,
            watchID: UUID(), watchStart: now
        ))
        XCTAssertFalse(consistent(
            lifting: watchStrength, mirror: true,
            watchID: watchStrength.workoutID,
            watchStart: now.addingTimeInterval(-100)
        ))
    }


    func testConfirmedWatchStrengthMirrorUsesRealHealthKitClockAndID() throws {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        var snapshot = WatchWorkoutLiveSnapshot(
            kind: .strength, state: .running, startedAt: start,
            capturedAt: start.addingTimeInterval(60),
            elapsedTime: 45, heartRate: 120,
            activeCalories: 16, distanceMeters: 0,
            averageHeartRate: nil, maxHeartRate: nil,
            routePointCount: 0
        )
        let id = UUID()
        snapshot.strengthWorkoutID = id
        let active = try XCTUnwrap(
            ATHLTHUniversalActiveCapture.mirroredStrength(
                snapshot, at: snapshot.capturedAt
            )
        )
        XCTAssertEqual(active.workoutID, id)
        XCTAssertNil(active.plannedSessionID)
        XCTAssertEqual(active.source, .watchMirror)
        XCTAssertFalse(active.source.isManualTiming)
        XCTAssertEqual(active.recordingOwner, .appleWatch)
        XCTAssertEqual(active.elapsedSeconds, 45)
        XCTAssertEqual(active.engine, .strength)
        XCTAssertEqual(active.phase, .work)
        XCTAssertNil(active.stageIndex, "Never invent a missing Watch cursor")

        snapshot.state = .paused
        snapshot.elapsedTime = 45
        let paused = try XCTUnwrap(
            ATHLTHUniversalActiveCapture.mirroredStrength(
                snapshot, at: snapshot.capturedAt
            )
        )
        XCTAssertEqual(paused.phase, .paused)
        XCTAssertEqual(paused.workoutID, active.workoutID)
        XCTAssertEqual(paused.elapsedSeconds, active.elapsedSeconds)
    }

    func testUnidentifiedOrStaleWatchMirrorKeepsOriginalSlotProtected() {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        var snapshot = WatchWorkoutLiveSnapshot(
            kind: .strength, state: .running, startedAt: start,
            capturedAt: start.addingTimeInterval(30),
            elapsedTime: 20, heartRate: 111,
            activeCalories: 5, distanceMeters: 0,
            averageHeartRate: nil, maxHeartRate: nil,
            routePointCount: 0
        )
        let now = snapshot.capturedAt
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredStrength(
            snapshot, at: now
        ))
        snapshot.strengthWorkoutID = UUID()
        snapshot.kind = .running
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredStrength(
            snapshot, at: now
        ))
        snapshot.kind = .strength
        snapshot.elapsedTime = 1_000
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredStrength(
            snapshot, at: now
        ))
        snapshot.elapsedTime = 20
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredStrength(
            snapshot, at: now.addingTimeInterval(45)
        ))
        snapshot.state = .completed
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredStrength(
            snapshot, at: now
        ))
    }

    func testAllNativeWatchSportsUseOneIdentifiedLiveCapture() throws {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let workoutID = UUID()
        let expected: [(WatchWorkoutKind, String, ATHLTHLiveWorkoutEngine)] = [
            (.running, "running", .endurance),
            (.walking, "walking", .endurance),
            (.cycling, "cycling", .cycling),
            (.rowing, "rowing", .endurance),
            (.stairClimbing, "stairclimber", .endurance),
            (.hiit, "hiit", .instructions),
            (.functional, "functional", .instructions),
            (.yoga, "yoga", .mobility),
            (.other, "other", .instructions)
        ]
        for (sport, category, engine) in expected {
            var snapshot = WatchWorkoutLiveSnapshot(
                kind: sport, state: .running, startedAt: start,
                capturedAt: start.addingTimeInterval(240),
                elapsedTime: 210, heartRate: 123,
                activeCalories: 30, distanceMeters: 0,
                averageHeartRate: nil, maxHeartRate: nil,
                routePointCount: 0
            )
            snapshot.universalWorkoutID = workoutID
            let active = try XCTUnwrap(
                ATHLTHUniversalActiveCapture.mirroredWatch(
                    snapshot, at: snapshot.capturedAt
                )
            )
            XCTAssertEqual(active.workoutID, workoutID)
            XCTAssertEqual(active.recordingOwner, .appleWatch)
            XCTAssertEqual(active.source, .watchMirror)
            XCTAssertEqual(active.activityCategory, category)
            XCTAssertEqual(active.engine, engine)
            XCTAssertEqual(active.elapsedSeconds, 210)
            snapshot.state = .paused
            let paused = try XCTUnwrap(
                ATHLTHUniversalActiveCapture.mirroredWatch(
                    snapshot, at: snapshot.capturedAt
                )
            )
            XCTAssertEqual(paused.workoutID, active.workoutID)
            XCTAssertEqual(paused.phase, .paused)
            XCTAssertEqual(paused.elapsedSeconds, active.elapsedSeconds)
        }
    }

    func testStaleUnidentifiedOrContradictoryWatchSessionCannotBeInvented() {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        var snapshot = WatchWorkoutLiveSnapshot(
            kind: .rowing, state: .running, startedAt: start,
            capturedAt: start.addingTimeInterval(90),
            elapsedTime: 60, heartRate: 122,
            activeCalories: 14, distanceMeters: 100,
            averageHeartRate: nil, maxHeartRate: nil,
            routePointCount: 0
        )
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            snapshot, at: snapshot.capturedAt
        ))
        snapshot.universalWorkoutID = UUID()
        snapshot.elapsedTime = 1000
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            snapshot, at: snapshot.capturedAt
        ))
        snapshot.elapsedTime = 60
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            snapshot, at: snapshot.capturedAt.addingTimeInterval(45)
        ))
        snapshot.state = .completed
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            snapshot, at: snapshot.capturedAt
        ))
        snapshot.state = .running
        snapshot.kind = .strength
        snapshot.strengthWorkoutID = UUID()
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            snapshot, at: snapshot.capturedAt
        ))
    }


    func testStaleSameAccountMirrorCannotClaimFreshSensorTelemetry() throws {
        let original = UUID(), owner = UUID()
        var mirror = WatchWorkoutLiveSnapshot(
            kind: .strength, state: .running,
            startedAt: started, capturedAt: started.addingTimeInterval(75),
            elapsedTime: 65, heartRate: 125, activeCalories: 20,
            distanceMeters: 0, averageHeartRate: nil,
            maxHeartRate: nil, routePointCount: 0
        )
        mirror.strengthWorkoutID = original
        mirror.universalWorkoutID = original
        mirror.accountOwnerID = owner
        XCTAssertEqual(mirror.accountOwnerID, owner)
        // After connectivity loss, current-account strength checkpoints may
        // persist, but this old mirror cannot become fresh live sensor data.
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            mirror, for: owner, at: mirror.capturedAt.addingTimeInterval(60)
        ))
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            mirror, for: UUID(), at: mirror.capturedAt
        ))
    }

    func testCurrentAccountWatchProjectionNeverLeaksAcrossLogin() throws {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let sourceOwner = UUID()
        let otherOwner = UUID()
        var mirror = WatchWorkoutLiveSnapshot(
            kind: .cycling, state: .running,
            startedAt: start, capturedAt: start.addingTimeInterval(85),
            elapsedTime: 70, heartRate: 140, activeCalories: 20,
            distanceMeters: 400, averageHeartRate: nil,
            maxHeartRate: nil, routePointCount: 0
        )
        let sessionID = UUID()
        mirror.universalWorkoutID = sessionID
        mirror.accountOwnerID = sourceOwner
        let matching = try XCTUnwrap(
            ATHLTHUniversalActiveCapture.mirroredWatch(
                mirror, for: sourceOwner, at: mirror.capturedAt
            )
        )
        XCTAssertEqual(matching.workoutID, sessionID)
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            mirror, for: otherOwner, at: mirror.capturedAt
        ))
        mirror.accountOwnerID = nil
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            mirror, for: sourceOwner, at: mirror.capturedAt
        ))
    }


    func testManualModesUseTheSameSportMappingAsStructuredBlocks() throws {
        for activity in CustomQuickWorkoutActivity.allCases {
            let mode = ATHLTHWorkoutSportMode(category: activity.rawValue)
            let original = timer(activity: activity, resumedAt: started)
            let state = try XCTUnwrap(ATHLTHUniversalActiveCapture.manual(
                original, at: started.addingTimeInterval(30)
            ))
            XCTAssertEqual(state.engine, mode.engine)
            XCTAssertEqual(state.workoutID, original.id)
            XCTAssertFalse(mode.title.isEmpty)
        }
    }


    func testPremirrorWatchHealthKitOccupiesSharedRecordingSlot() {
        XCTAssertTrue(ATHLTHPreMirrorWatchCapturePolicy.permitsExisting(
            nil, watchActive: false
        ))
        XCTAssertFalse(ATHLTHPreMirrorWatchCapturePolicy.permitsExisting(
            nil, watchActive: true
        ))

        let started = Date(timeIntervalSince1970: 1_900_000_000)
        func original(_ owner: ATHLTHWorkoutRecordingOwner,
                      _ source: ATHLTHUniversalCaptureSource)
            -> ATHLTHUniversalActiveCaptureState {
            ATHLTHUniversalActiveCaptureState(
                workoutID: UUID(), plannedSessionID: nil,
                recordingOwner: owner, source: source,
                activityCategory: "strength", engine: .strength,
                phase: .work, startedAt: started,
                elapsedSeconds: 60, stageIndex: nil, stageCount: nil
            )
        }
        XCTAssertFalse(ATHLTHPreMirrorWatchCapturePolicy.permitsExisting(
            original(.iPhone, .phoneRunWalk), watchActive: true
        ))
        XCTAssertFalse(ATHLTHPreMirrorWatchCapturePolicy.permitsExisting(
            original(.iPhone, .manualTimer), watchActive: true
        ))
        XCTAssertFalse(ATHLTHPreMirrorWatchCapturePolicy.permitsExisting(
            original(.appleWatch, .watchMirror), watchActive: true
        ))
        XCTAssertTrue(ATHLTHPreMirrorWatchCapturePolicy.permitsExisting(
            original(.appleWatch, .strength), watchActive: true
        ))
    }


    func testStructuredWorkoutChangesSportWithoutChangingOriginalRecording() throws {
        var cycle = block(kind: .note, sequence: 1)
        cycle.activityTag = "cycling"
        let recovery = block(kind: .rest, sequence: 2)
        let strength = block(kind: .exercise, sequence: 3)
        let watchFreeID = UUID()
        let stages = [cycle, recovery, strength]
        for (index, expectedSport, expectedEngine) in [
            (0, "cycling", ATHLTHLiveWorkoutEngine.cycling),
            (1, "recovery", .recovery),
            (2, "strength", .strength)
        ] {
            let saved = ATHLTHStructuredWorkoutCheckpoint(
                workoutID: watchFreeID,
                savedAt: started, startedAt: started,
                stepEnteredAt: started, currentIndex: index,
                completedIDs: [], results: [:], modeStarts: [:],
                executionBlocks: stages, emomWaiting: false,
                timedOutGroups: [], enteredReps: 0, enteredWeight: ""
            )
            let projected = try XCTUnwrap(
                ATHLTHUniversalActiveCapture.structured(
                    saved, at: started.addingTimeInterval(90)
                )
            )
            XCTAssertEqual(projected.workoutID, watchFreeID)
            XCTAssertEqual(projected.recordingOwner, .iPhone)
            XCTAssertEqual(projected.source, .structuredTimer)
            XCTAssertEqual(projected.startedAt, started)
            XCTAssertEqual(projected.activityCategory, expectedSport)
            XCTAssertEqual(projected.engine, expectedEngine)
            XCTAssertEqual(projected.stageIndex, index)
        }
    }

    func testCanonicalSportCodesRoundTripAcrossAllActivityModes() {
        let all: [ATHLTHWorkoutSportMode] = [
            .running, .walking, .strength, .cycling, .rowing,
            .stairClimber, .hiit, .circuit, .functional, .yoga,
            .meditation, .mobility, .sports, .other, .recovery,
            .instructions
        ]
        for mode in all {
            XCTAssertEqual(
                ATHLTHWorkoutSportMode(category: mode.category), mode,
                mode.category
            )
        }
    }


    func testWatchHybridChangesActiveSportWithoutChangingCaptureOwner() throws {
        let id = UUID(), owner = UUID(), planned = UUID()
        var mirror = WatchWorkoutLiveSnapshot(
            kind: .strength, state: .running, startedAt: started,
            capturedAt: started.addingTimeInterval(180),
            elapsedTime: 160, heartRate: 155,
            activeCalories: 65, distanceMeters: 800,
            averageHeartRate: nil, maxHeartRate: nil,
            routePointCount: 0
        )
        mirror.strengthWorkoutID = id
        mirror.universalWorkoutID = id
        mirror.accountOwnerID = owner
        mirror.plannedCalendarSessionID = planned

        mirror.strengthHybridRunningActive = true
        mirror.strengthRecoveryActive = false
        let run = try XCTUnwrap(ATHLTHUniversalActiveCapture.mirroredWatch(
            mirror, for: owner, at: mirror.capturedAt
        ))
        XCTAssertEqual(run.workoutID, id)
        XCTAssertEqual(run.plannedSessionID, planned)
        XCTAssertEqual(run.activityCategory, "running")
        XCTAssertEqual(run.engine, .endurance)
        XCTAssertEqual(run.phase, .work)
        XCTAssertEqual(run.recordingOwner, .appleWatch)

        mirror.strengthRecoveryActive = true
        let rest = try XCTUnwrap(ATHLTHUniversalActiveCapture.mirroredWatch(
            mirror, for: owner, at: mirror.capturedAt
        ))
        XCTAssertEqual(rest.workoutID, id)
        XCTAssertEqual(rest.activityCategory, "recovery")
        XCTAssertEqual(rest.engine, .recovery)
        XCTAssertEqual(rest.phase, .recovery)

        mirror.state = .paused
        let paused = try XCTUnwrap(ATHLTHUniversalActiveCapture.mirroredWatch(
            mirror, for: owner, at: mirror.capturedAt
        ))
        XCTAssertEqual(paused.phase, .paused)
        XCTAssertEqual(paused.workoutID, id)

        mirror.state = .running
        mirror.strengthRecoveryActive = false
        mirror.strengthHybridRunningActive = false
        let lifting = try XCTUnwrap(ATHLTHUniversalActiveCapture.mirroredWatch(
            mirror, for: owner, at: mirror.capturedAt
        ))
        XCTAssertEqual(lifting.activityCategory, "strength")
        XCTAssertEqual(lifting.engine, .strength)
        XCTAssertEqual(lifting.workoutID, id)

        // An incorrectly attached hybrid flag may never turn another
        // native sport into a strength or running HealthKit recording.
        mirror.kind = .cycling
        mirror.strengthHybridRunningActive = true
        XCTAssertEqual(
            ATHLTHWatchLiveSportPolicy.activityCategory(mirror), "cycling"
        )
    }

    func testWatchStrengthSetCursorIsValidatedWithoutCreatingNewStages() throws {
        let now = started.addingTimeInterval(120)
        let owner = UUID(), workoutID = UUID()
        var snapshot = WatchWorkoutLiveSnapshot(
            kind: .strength, state: .running, startedAt: started,
            capturedAt: now, elapsedTime: 115,
            heartRate: 125, activeCalories: 25,
            distanceMeters: 0, averageHeartRate: nil,
            maxHeartRate: nil, routePointCount: 0
        )
        snapshot.accountOwnerID = owner
        snapshot.universalWorkoutID = workoutID
        snapshot.strengthWorkoutID = workoutID
        snapshot.strengthHybridRunningActive = true
        snapshot.strengthSetIndex = 2
        snapshot.strengthSetCount = 4
        let run = try XCTUnwrap(
            ATHLTHUniversalActiveCapture.mirroredWatch(
                snapshot, for: owner, at: now
            )
        )
        XCTAssertEqual(run.stageIndex, 1)
        XCTAssertEqual(run.stageCount, 4)
        XCTAssertEqual(run.activityCategory, "running")
        XCTAssertEqual(run.workoutID, workoutID)

        snapshot.strengthRecoveryActive = true
        let rest = try XCTUnwrap(
            ATHLTHUniversalActiveCapture.mirroredWatch(
                snapshot, for: owner, at: now
            )
        )
        XCTAssertEqual(rest.stageIndex, 1)
        XCTAssertEqual(rest.stageCount, 4)
        XCTAssertEqual(rest.phase, .recovery)

        // Legacy snapshots may not have a cursor. Never infer one from
        // elapsed time, exercise name or a synthetic hybrid step count.
        snapshot.strengthSetIndex = nil
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            snapshot, for: owner, at: now
        )?.stageIndex)
        snapshot.strengthSetIndex = 0
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            snapshot, for: owner, at: now
        )?.stageIndex)
        snapshot.strengthSetIndex = 5
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            snapshot, for: owner, at: now
        )?.stageIndex)
        snapshot.strengthSetIndex = 2
        snapshot.strengthSetCount = 0
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            snapshot, for: owner, at: now
        )?.stageIndex)
        snapshot.strengthSetCount = 4
        XCTAssertNil(ATHLTHUniversalActiveCapture.mirroredWatch(
            snapshot, for: UUID(), at: now
        ))
    }

    func testStructuredWellnessKeepsActiveYogaAndMeditationIdentity() throws {
        for (isYoga, expected) in [
            (true, "yoga"), (false, "meditation")
        ] {
            var stage = block(kind: .note, sequence: 1)
            stage.wellnessKind = isYoga ? .yoga : .meditation
            let workoutID = UUID()
            let checkpoint = ATHLTHStructuredWorkoutCheckpoint(
                workoutID: workoutID, savedAt: started,
                startedAt: started, stepEnteredAt: started,
                currentIndex: 0, completedIDs: [], results: [:],
                modeStarts: [:], executionBlocks: [stage],
                emomWaiting: false, timedOutGroups: [],
                enteredReps: 0, enteredWeight: ""
            )
            let active = try XCTUnwrap(
                ATHLTHUniversalActiveCapture.structured(
                    checkpoint, at: started.addingTimeInterval(30)
                )
            )
            XCTAssertEqual(active.activityCategory, expected)
            XCTAssertEqual(active.engine, .mobility)
            XCTAssertEqual(active.workoutID, workoutID)
        }
    }

    func testStructuredPlanIdentitySurvivesCursorRecovery() throws {
        let planID = UUID(), workoutID = UUID()
        let step = block(kind: .note, sequence: 1)
        let original = ATHLTHStructuredWorkoutCheckpoint(
            workoutID: workoutID, sourcePlanID: planID,
            savedAt: started, startedAt: started,
            stepEnteredAt: started, currentIndex: 0,
            completedIDs: [], results: [:], modeStarts: [:],
            executionBlocks: [step], emomWaiting: false,
            timedOutGroups: [], enteredReps: 0, enteredWeight: ""
        )
        let recovered = try JSONDecoder().decode(
            ATHLTHStructuredWorkoutCheckpoint.self,
            from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(recovered.workoutID, workoutID)
        XCTAssertEqual(recovered.sourcePlanID, planID)
        let state = try XCTUnwrap(ATHLTHUniversalActiveCapture.structured(
            recovered, at: started.addingTimeInterval(90)
        ))
        XCTAssertEqual(state.workoutID, workoutID)
        XCTAssertEqual(state.plannedSessionID, workoutID)
        XCTAssertEqual(state.recordingOwner, .iPhone)
        XCTAssertEqual(state.source, .structuredTimer)
        XCTAssertEqual(state.elapsedSeconds, 90)
    }


    func testWatchPlannedLiveIdentitySurvivesPauseAndLegacyDecoding() throws {
        let planned = UUID(), owner = UUID(), original = UUID()
        let kinds: [WatchWorkoutKind] = [
            .running, .walking, .strength, .cycling, .rowing,
            .stairClimbing, .hiit, .functional, .yoga, .other
        ]
        for kind in kinds {
            var snapshot = WatchWorkoutLiveSnapshot(
                kind: kind, state: .running, startedAt: started,
                capturedAt: started.addingTimeInterval(90),
                elapsedTime: 75, heartRate: 125,
                activeCalories: 20, distanceMeters: 0,
                averageHeartRate: nil, maxHeartRate: nil,
                routePointCount: 0
            )
            snapshot.universalWorkoutID = original
            snapshot.accountOwnerID = owner
            if kind == .strength { snapshot.strengthWorkoutID = original }
            snapshot.plannedCalendarSessionID = planned
            let decoded = try JSONDecoder().decode(
                WatchWorkoutLiveSnapshot.self,
                from: JSONEncoder().encode(snapshot)
            )
            let live = try XCTUnwrap(
                ATHLTHUniversalActiveCapture.mirroredWatch(
                    decoded, for: owner, at: decoded.capturedAt
                )
            )
            XCTAssertEqual(live.workoutID, original)
            XCTAssertEqual(live.plannedSessionID, planned, kind.rawValue)
            XCTAssertNil(
                ATHLTHUniversalActiveCapture.mirroredWatch(
                    decoded, for: UUID(), at: decoded.capturedAt
                )
            )
            snapshot.state = .paused
            let paused = try XCTUnwrap(
                ATHLTHUniversalActiveCapture.mirroredWatch(
                    snapshot, for: owner, at: snapshot.capturedAt
                )
            )
            XCTAssertEqual(paused.phase, .paused)
            XCTAssertEqual(paused.plannedSessionID, planned)
            snapshot.plannedCalendarSessionID = nil
            let free = try XCTUnwrap(
                ATHLTHUniversalActiveCapture.mirroredWatch(
                    snapshot, for: owner, at: snapshot.capturedAt
                )
            )
            XCTAssertNil(free.plannedSessionID)
        }

        var legacy = WatchWorkoutLiveSnapshot(
            kind: .cycling, state: .running, startedAt: started,
            capturedAt: started.addingTimeInterval(90),
            elapsedTime: 75, heartRate: 125,
            activeCalories: 20, distanceMeters: 0,
            averageHeartRate: nil, maxHeartRate: nil,
            routePointCount: 0
        )
        legacy.universalWorkoutID = original
        legacy.accountOwnerID = owner
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(legacy)
            ) as? [String: Any]
        )
        json.removeValue(forKey: "plannedCalendarSessionID")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decodedLegacy = try JSONDecoder().decode(
            WatchWorkoutLiveSnapshot.self, from: legacyData
        )
        XCTAssertNil(decodedLegacy.plannedCalendarSessionID)
        let restored = try XCTUnwrap(
            ATHLTHUniversalActiveCapture.mirroredWatch(
                decodedLegacy, for: owner, at: decodedLegacy.capturedAt
            )
        )
        XCTAssertEqual(restored.workoutID, original)
        XCTAssertNil(restored.plannedSessionID)
    }

}
