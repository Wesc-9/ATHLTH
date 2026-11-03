import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHEditedRunningWatchTransferTests: XCTestCase {
    private func planned(
        _ blocks: [WorkoutTemplateBlock], title: String = "Intervals"
    ) -> PlannedSession {
        var workout = PlannedSession(
            id: UUID(), title: title, kind: .running,
            scheduledStart: nil,
            durationMinutes: ATHLTHWorkoutDurationEstimator.minutes(for: blocks),
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        workout.workoutBlocks = blocks
        return workout
    }

    func testThirtyThirtyPreservesAllFortyWatchStepsAndLastActiveRecovery() throws {
        let blocks = ATHLTHRunningExercisePreset.thirtyThirty.blocks(in: .main)
        let workout = planned(blocks, title: "30/30")
        let transfer = PlannedWorkoutWatchBuilder.runningTransfer(
            from: workout, routeAlerts: .standard
        )
        XCTAssertEqual(transfer.sourceWorkoutID, workout.id)
        XCTAssertEqual(transfer.steps.count, 40)
        XCTAssertEqual(transfer.steps.filter { $0.phase == "work" }.count, 20)
        XCTAssertEqual(transfer.steps.filter { $0.phase == "recovery" }.count, 20)
        XCTAssertEqual(transfer.steps.map(\.durationSeconds),
                       Array(repeating: 30.0, count: 40))
        XCTAssertEqual(transfer.steps.last?.phase, "recovery")
        XCTAssertEqual(transfer.autoAdvanceTimedSteps, true)
        XCTAssertNil(transfer.steps[1].coachBrief)

        let restored = try JSONDecoder().decode(
            WatchRunningWorkoutTransfer.self,
            from: JSONEncoder().encode(transfer)
        )
        XCTAssertEqual(restored.steps.count, 40)
        XCTAssertEqual(restored.sourceWorkoutID, workout.id)
        XCTAssertFalse(ATHLTHRunningStepEngine.isCompleted(
            step: restored.steps[0], elapsedTime: 29,
            distanceMeters: 0, stepStartElapsedTime: 0,
            stepStartDistanceMeters: 0
        ))
        XCTAssertTrue(ATHLTHRunningStepEngine.isCompleted(
            step: restored.steps[0], elapsedTime: 30,
            distanceMeters: 0, stepStartElapsedTime: 0,
            stepStartDistanceMeters: 0
        ))
    }

    func testFourByFourWatchTransferRetainsFourthRecoveryAndPerDragTargets() throws {
        var blocks = ATHLTHRunningExercisePreset.fourByFour.blocks(in: .main)
        blocks[0].targetPaceSecondsPerKilometer = 300
        blocks[0].targetHeartRateZone = 4
        blocks[2].targetPaceSecondsPerKilometer = 270
        blocks[2].targetHeartRateZone = 5
        let workout = planned(blocks, title: "4 × 4")
        let transfer = PlannedWorkoutWatchBuilder.runningTransfer(
            from: workout, routeAlerts: .standard
        )
        XCTAssertEqual(transfer.steps.count, 8)
        XCTAssertEqual(transfer.steps.filter { $0.phase == "work" }.count, 4)
        XCTAssertEqual(transfer.steps.filter { $0.phase == "recovery" }.count, 4)
        XCTAssertEqual(transfer.steps[0].targetPaceMinSecondsPerKilometer, 300)
        XCTAssertEqual(transfer.steps[0].targetHeartRateZone, 4)
        XCTAssertEqual(transfer.steps[2].targetPaceMinSecondsPerKilometer, 270)
        XCTAssertEqual(transfer.steps[2].targetHeartRateZone, 5)
        XCTAssertEqual(transfer.steps[1].phase, "recovery")
        XCTAssertEqual(transfer.steps.last?.durationSeconds, 180)
    }

    func testTreadmillSpeedInclineAndDistanceTargetsReachWatch() throws {
        var blocks = ATHLTHRunningExercisePreset.treadmill.blocks(in: .main)
        blocks[0].targetPaceSecondsPerKilometer = 360
        blocks[0].treadmillInclinePercent = 2
        blocks[0].targetHeartRateZone = 3
        let transfer = PlannedWorkoutWatchBuilder.runningTransfer(
            from: planned(blocks), routeAlerts: .standard
        )
        XCTAssertEqual(transfer.steps.count, 1)
        XCTAssertEqual(transfer.steps[0].durationSeconds, 1_200)
        XCTAssertEqual(transfer.steps[0].targetPaceMinSecondsPerKilometer, 360)
        XCTAssertEqual(transfer.steps[0].targetTreadmillInclinePercent, 2)
        XCTAssertEqual(transfer.steps[0].targetHeartRateZone, 3)
        XCTAssertEqual(transfer.treadmillInclinePercent, 2)

        let distance = ATHLTHRunningExercisePreset.sixByFourHundred.blocks(in: .main)
        let watch = PlannedWorkoutWatchBuilder.runningTransfer(
            from: planned(distance), routeAlerts: .standard
        )
        XCTAssertEqual(watch.steps.count, 12)
        XCTAssertEqual(watch.steps.filter { $0.phase == "work" }.count, 6)
        XCTAssertEqual(watch.steps.filter { $0.phase == "recovery" }.count, 6)
        XCTAssertEqual(watch.steps[0].measure, .distance)
        XCTAssertEqual(watch.steps[0].distanceMeters, 400)
        XCTAssertEqual(watch.steps[1].measure, .time)
        XCTAssertEqual(watch.steps[1].durationSeconds, 90)
    }

    func testLegacyRunningTemplateStillUsesItsExistingWatchBuilder() throws {
        var workout = planned([], title: "Legacy")
        workout.runningWorkout = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first {
                $0.title == "4 × 4 intervaller"
            }
        )
        let transfer = PlannedWorkoutWatchBuilder.runningTransfer(
            from: workout, routeAlerts: .standard
        )
        XCTAssertEqual(transfer.steps.count, 9)
        XCTAssertEqual(transfer.steps.filter { $0.phase == "recovery" }.count, 3)
    }
}
