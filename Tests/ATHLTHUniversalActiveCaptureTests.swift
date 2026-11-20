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

}
