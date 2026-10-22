import XCTest
@testable import ATHLTH

final class WatchRunningWorkoutAppendCommandTests: XCTestCase {
    func testAppendPayloadPreservesWorkoutIdentityAndIntervals() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let id = UUID()
        let step = WatchRunningWorkoutStep(
            id: UUID(),
            title: "4 × 4",
            measure: .time,
            distanceMeters: nil,
            durationSeconds: 240,
            intensityText: "Work"
        )
        let addition = WatchRunningWorkoutTransfer(
            title: "4 × 4",
            steps: [step]
        )
        let payload = WatchWorkoutMirrorCommand(
            command: .appendRunningWorkout,
            workoutStartedAt: startedAt,
            runningWorkoutToAppend: addition,
            runningWorkoutStartImmediately: true,
            commandID: id
        )

        let decoded = try JSONDecoder().decode(
            WatchWorkoutMirrorCommand.self,
            from: JSONEncoder().encode(payload)
        )
        XCTAssertEqual(decoded.command, .appendRunningWorkout)
        XCTAssertEqual(decoded.workoutStartedAt, startedAt)
        XCTAssertEqual(decoded.runningWorkoutToAppend?.steps.count, 1)
        XCTAssertEqual(decoded.runningWorkoutStartImmediately, true)
        XCTAssertEqual(decoded.commandID, id)
    }

    func testExistingPausePayloadStillDecodesWithoutAppendProperties() throws {
        let legacy = #"{"command":"pause"}"#
        let decoded = try JSONDecoder().decode(
            WatchWorkoutMirrorCommand.self,
            from: Data(legacy.utf8)
        )
        XCTAssertEqual(decoded.command, .pause)
        XCTAssertNil(decoded.runningWorkoutToAppend)
        XCTAssertNil(decoded.runningWorkoutStartImmediately)
        XCTAssertNil(decoded.commandID)
    }
}
