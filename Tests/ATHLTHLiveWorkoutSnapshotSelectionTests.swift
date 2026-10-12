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
