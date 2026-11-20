import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCustomWorkoutTimelineTests: XCTestCase {
    private func state(
        method: CustomQuickWorkoutMethod,
        time: TimeInterval,
        paused: Bool = false
    ) throws -> ATHLTHCustomWorkoutTimeline.Snapshot {
        try XCTUnwrap(ATHLTHCustomWorkoutTimeline.state(
            method: method, durationMinutes: 10,
            workSeconds: 40, restSeconds: 20,
            rounds: 3, elapsedSeconds: time, isPaused: paused
        ))
    }

    func testTraditionalIntervalsHaveOneOrderedTimeline() throws {
        let first = try state(method: .intervals, time: 0)
        XCTAssertEqual(first.stageIndex, 0)
        XCTAssertEqual(first.stageCount, 5)
        XCTAssertEqual(first.roundNumber, 1)
        XCTAssertEqual(first.phase, .work)
        XCTAssertEqual(first.remainingSeconds, 40)

        let rest = try state(method: .intervals, time: 40)
        XCTAssertEqual(rest.stageIndex, 1)
        XCTAssertEqual(rest.phase, .recovery)
        XCTAssertEqual(rest.remainingSeconds, 20)

        let second = try state(method: .intervals, time: 60)
        XCTAssertEqual(second.stageIndex, 2)
        XCTAssertEqual(second.roundNumber, 2)
        XCTAssertEqual(second.phase, .work)

        let end = try state(method: .intervals, time: 160)
        XCTAssertTrue(end.intervalsComplete)
        XCTAssertEqual(end.stageIndex, 4)
        XCTAssertEqual(end.remainingSeconds, 0)
        XCTAssertNotEqual(end.phase, .completed,
            "Finishing the intervals cannot silently finish the workout")
    }

    func testTabataAlwaysUsesTwentyTenNotUnrelatedDefaults() throws {
        let rest = try state(method: .tabata, time: 22)
        XCTAssertEqual(rest.stageIndex, 1)
        XCTAssertEqual(rest.phase, .recovery)
        XCTAssertEqual(rest.remainingSeconds, 8)

        let second = try state(method: .tabata, time: 30)
        XCTAssertEqual(second.roundNumber, 2)
        XCTAssertEqual(second.stageIndex, 2)
        XCTAssertEqual(second.phase, .work)

        let done = try state(method: .tabata, time: 80)
        XCTAssertTrue(done.intervalsComplete)
        XCTAssertEqual(done.stageIndex, 4)
        XCTAssertEqual(done.stageCount, 5)
        XCTAssertEqual(done.remainingSeconds, 0)
    }

    func testPausedTimelineFreezesItsPhaseWhilePreservingIndex() throws {
        let rest = try state(method: .intervals, time: 45)
        let paused = try state(method: .intervals, time: 45, paused: true)
        XCTAssertEqual(paused.phase, .paused)
        XCTAssertEqual(paused.stageIndex, rest.stageIndex)
        XCTAssertEqual(paused.remainingSeconds, rest.remainingSeconds)
    }

    func testEmomCapsLastMinuteAndNeverInventsExtraRounds() throws {
        let beforeCap = try state(method: .emom, time: 599)
        XCTAssertEqual(beforeCap.roundNumber, 10)
        XCTAssertEqual(beforeCap.stageIndex, 9)
        XCTAssertEqual(beforeCap.stageCount, 10)
        XCTAssertEqual(beforeCap.remainingSeconds, 1)

        let completed = try state(method: .emom, time: 610)
        XCTAssertEqual(completed.roundNumber, 10)
        XCTAssertEqual(completed.stageIndex, 9)
        XCTAssertTrue(completed.intervalsComplete)
        XCTAssertEqual(completed.remainingSeconds, 0)
    }

    func testAmrapAndForTimeShareOneRemainingTimePolicy() throws {
        for method in [CustomQuickWorkoutMethod.amrap, .forTime] {
            let active = try state(method: method, time: 440)
            XCTAssertEqual(active.remainingSeconds, 160)
            XCTAssertNil(active.stageIndex)
            XCTAssertFalse(active.intervalsComplete)
            let capped = try state(method: method, time: 700)
            XCTAssertEqual(capped.remainingSeconds, 0)
            XCTAssertTrue(capped.intervalsComplete)
        }
    }

    func testInvalidElapsedNeverTurnsIntoFalseWorkoutState() {
        for value in [Double.nan, .infinity, -1, 90_000] {
            XCTAssertNil(ATHLTHCustomWorkoutTimeline.state(
                method: .intervals, durationMinutes: 10,
                workSeconds: 40, restSeconds: 20, rounds: 3,
                elapsedSeconds: value, isPaused: false
            ))
        }
    }

    func testPausedZeroRestIntervalsAreNeverLabelledAsRest() throws {
        let zeroRest = try XCTUnwrap(ATHLTHCustomWorkoutTimeline.state(
            method: .intervals, durationMinutes: 10,
            workSeconds: 40, restSeconds: 0, rounds: 3,
            elapsedSeconds: 41, isPaused: true
        ))
        XCTAssertEqual(zeroRest.stageIndex, 1)
        XCTAssertEqual(zeroRest.phase, .paused)
        XCTAssertFalse(zeroRest.inRestInterval)
        let actualRest = try state(method: .tabata, time: 22, paused: true)
        XCTAssertTrue(actualRest.inRestInterval)
        XCTAssertEqual(actualRest.phase, .paused)
    }

}
