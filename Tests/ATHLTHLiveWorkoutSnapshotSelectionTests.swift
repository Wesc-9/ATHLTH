import XCTest
@testable import ATHLTH

final class ATHLTHLiveWorkoutSnapshotSelectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(
        kind: WatchWorkoutKind,
        elapsed: TimeInterval,
        at date: Date,
        state: WatchWorkoutMirrorState = .running
    ) -> WatchWorkoutLiveSnapshot {
        WatchWorkoutLiveSnapshot(
            kind: kind,
            state: state,
            startedAt: date,
            capturedAt: date,
            elapsedTime: elapsed,
            heartRate: 120,
            activeCalories: 70,
            distanceMeters: 1_000,
            averageHeartRate: nil,
            maxHeartRate: nil,
            routePointCount: 0
        )
    }

    func testPhoneWorkoutSurvivesMirroringRemoval() throws {
        let phone = snapshot(kind: .running, elapsed: 325, at: now)
        let selected = try XCTUnwrap(
            ATHLTHLiveWorkoutSnapshotSelection.resolve(
                mirroredWatch: nil, phoneWorkout: phone
            )
        )
        XCTAssertEqual(selected, phone)
        XCTAssertEqual(selected.elapsedTime, 325)
    }

    func testActiveWatchStillOwnsMirroredPresentation() throws {
        let watch = snapshot(kind: .strength, elapsed: 80, at: now)
        let phone = snapshot(
            kind: .running, elapsed: 120, at: now.addingTimeInterval(1)
        )
        XCTAssertEqual(
            ATHLTHLiveWorkoutSnapshotSelection.resolve(
                mirroredWatch: watch, phoneWorkout: phone
            ),
            watch
        )
    }

    func testTerminalWatchCannotHideNewPhoneWorkout() {
        for terminal: WatchWorkoutMirrorState in [
            .ending, .completed, .failed
        ] {
            for active: WatchWorkoutMirrorState in [
                .preparing, .running, .paused
            ] {
                let phone = snapshot(
                    kind: .running, elapsed: 24,
                    at: now.addingTimeInterval(600), state: active
                )
                let oldWatch = snapshot(
                    kind: .strength, elapsed: 360,
                    at: now, state: terminal
                )
                XCTAssertEqual(
                    ATHLTHLiveWorkoutSnapshotSelection.resolve(
                        mirroredWatch: oldWatch, phoneWorkout: phone
                    ),
                    phone
                )
            }
        }
    }

    func testTerminalWatchRemainsWhenThereIsNoNewActivePhoneWorkout() {
        let watch = snapshot(
            kind: .walking, elapsed: 540,
            at: now, state: .completed
        )
        let oldPhone = snapshot(
            kind: .running, elapsed: 900,
            at: now, state: .completed
        )
        XCTAssertEqual(
            ATHLTHLiveWorkoutSnapshotSelection.resolve(
                mirroredWatch: watch, phoneWorkout: oldPhone
            ),
            watch
        )
        XCTAssertEqual(
            ATHLTHLiveWorkoutSnapshotSelection.resolve(
                mirroredWatch: watch, phoneWorkout: nil
            ),
            watch
        )
    }

    private func strengthSession(
        resting: Bool = true,
        startedAt: Date
    ) -> WatchStrengthSessionSnapshot {
        WatchStrengthSessionSnapshot(
            workoutID: UUID(),
            title: "Styrke",
            exerciseIndex: 0,
            exerciseCount: 2,
            exerciseName: "Rowing Machine",
            primaryMuscles: [],
            setIndex: 2,
            setCount: 3,
            setNumber: 3,
            completedSets: 3,
            totalSets: 6,
            draftReps: 10,
            draftWeightKilograms: 0,
            draftRestSeconds: 90,
            isResting: resting,
            restEndsAt: resting ? startedAt.addingTimeInterval(90) : nil,
            currentExerciseComplete: true,
            hasNextExercise: true,
            allExercisesComplete: false,
            updatedAt: startedAt.addingTimeInterval(5)
        )
    }

    func testCurrentPhoneStrengthSetReplacesStaleWatchPresentation() throws {
        var watch = snapshot(kind: .strength, elapsed: 110, at: now)
        watch.strengthExerciseName = "Machine Chest Fly"
        watch.strengthSetIndex = 2
        watch.strengthSetCount = 3
        watch.strengthRestEndsAt = nil
        let result = try XCTUnwrap(
            ATHLTHLiveWorkoutSnapshotSelection.enrichStrength(
                watch,
                local: strengthSession(startedAt: now),
                localStartedAt: now,
                displayName: "Romaskin"
            )
        )
        XCTAssertEqual(result.heartRate, 120)
        XCTAssertEqual(result.strengthExerciseName, "Romaskin")
        XCTAssertEqual(result.strengthSetIndex, 3)
        XCTAssertEqual(result.strengthSetCount, 3)
        XCTAssertEqual(result.strengthRestEndsAt, now.addingTimeInterval(90))
        XCTAssertNil(result.strengthTimedSetTargetSeconds)
    }

    func testUnrelatedStrengthSessionNeverChangesWatchLiveActivity() throws {
        var watch = snapshot(kind: .strength, elapsed: 110, at: now)
        watch.strengthExerciseName = "Machine Chest Fly"
        let result = try XCTUnwrap(
            ATHLTHLiveWorkoutSnapshotSelection.enrichStrength(
                watch,
                local: strengthSession(startedAt: now),
                localStartedAt: now.addingTimeInterval(3_600),
                displayName: "Romaskin"
            )
        )
        XCTAssertEqual(result, watch)
    }

    func testNoWorkoutDoesNotInventSession() {
        XCTAssertNil(
            ATHLTHLiveWorkoutSnapshotSelection.resolve(
                mirroredWatch: nil, phoneWorkout: nil
            )
        )
    }

    func testHandoffPreservesPhoneWorkoutIdentity() throws {
        let phone = snapshot(
            kind: .walking, elapsed: 50,
            at: now.addingTimeInterval(700)
        )
        let oldWatch = snapshot(
            kind: .strength, elapsed: 1_000,
            at: now, state: .completed
        )
        let selected = try XCTUnwrap(
            ATHLTHLiveWorkoutSnapshotSelection.resolve(
                mirroredWatch: oldWatch, phoneWorkout: phone
            )
        )
        XCTAssertEqual(selected.startedAt, phone.startedAt)
        XCTAssertEqual(selected.kind, .walking)
        XCTAssertEqual(selected.capturedAt, phone.capturedAt)
    }
}
