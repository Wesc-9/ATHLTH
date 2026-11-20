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
        XCTAssertEqual(state.activityCategory, "hybrid")
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

}
