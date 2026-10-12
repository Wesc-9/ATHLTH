import XCTest
@testable import ATHLTH

final class ATHLTHLiveWorkoutSnapshotSelectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(
        kind: WatchWorkoutKind,
        elapsed: TimeInterval,
        at date: Date
    ) -> WatchWorkoutLiveSnapshot {
        WatchWorkoutLiveSnapshot(
            kind: kind,
            state: .running,
            startedAt: now,
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
        let selected = try XCTUnwrap(
            ATHLTHLiveWorkoutSnapshotSelection.resolve(
                mirroredWatch: watch, phoneWorkout: phone
            )
        )
        XCTAssertEqual(selected, watch)
    }

    func testNoWorkoutEndsPresentationInsteadOfInventingSession() {
        XCTAssertNil(
            ATHLTHLiveWorkoutSnapshotSelection.resolve(
                mirroredWatch: nil, phoneWorkout: nil
            )
        )
    }

    func testChangedSourceDoesNotChangeWorkoutIdentity() throws {
        let phone = snapshot(kind: .walking, elapsed: 50, at: now)
        let selected = try XCTUnwrap(
            ATHLTHLiveWorkoutSnapshotSelection.resolve(
                mirroredWatch: nil, phoneWorkout: phone
            )
        )
        XCTAssertEqual(selected.startedAt, phone.startedAt)
        XCTAssertEqual(selected.kind, .walking)
        XCTAssertEqual(selected.capturedAt, phone.capturedAt)
    }
}
