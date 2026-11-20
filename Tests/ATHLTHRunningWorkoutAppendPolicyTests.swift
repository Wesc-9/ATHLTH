import XCTest
@testable import ATHLTH

final class ATHLTHRunningWorkoutAppendPolicyTests: XCTestCase {
    private func step(
        measure: WatchRunningStepMeasure = .time,
        seconds: Double? = 60,
        meters: Double? = nil
    ) -> WatchRunningWorkoutStep {
        WatchRunningWorkoutStep(
            id: UUID(),
            title: "Interval",
            measure: measure,
            distanceMeters: meters,
            durationSeconds: seconds,
            intensityText: nil
        )
    }

    func testNewWorkoutCanStartNowWithoutInterruptingCurrentRecording() {
        XCTAssertTrue(ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: false,
            startNow: true,
            steps: [step()]
        ))
        XCTAssertTrue(ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: false,
            startNow: false,
            steps: [step()]
        ), "Selecting intervals while free running queues them for manual Next")
    }

    func testActiveIntervalsMayBeQueuedButNotOverwritten() {
        XCTAssertTrue(ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: true,
            startNow: false,
            steps: [step()]
        ))
        XCTAssertFalse(ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: true,
            startNow: true,
            steps: [step()]
        ))
    }

    func testInvalidAndMissingTargetsAreNotAppended() {
        XCTAssertFalse(ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: false,
            startNow: true,
            steps: []
        ))
        XCTAssertFalse(ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: false,
            startNow: true,
            steps: [step(seconds: .nan)]
        ))
        XCTAssertFalse(ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: false,
            startNow: true,
            steps: [step(measure: .distance, seconds: nil, meters: 0)]
        ))
        XCTAssertTrue(ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: false,
            startNow: true,
            steps: [step(measure: .distance, seconds: nil, meters: 1000)]
        ))
    }

    func testExcessiveIntervalCountIsRejected() {
        XCTAssertFalse(ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: false,
            startNow: true,
            steps: (0..<151).map { _ in step() }
        ))
    }
    func testExistingFreeRunningDropsDuplicateWarmupAndWaitsForManualAdvance() {
        let warmup = WatchRunningWorkoutStep(
            id: UUID(), title: "10 minute warmup", measure: .time,
            distanceMeters: nil, durationSeconds: 600,
            intensityText: nil, phase: "warmup"
        )
        let interval = WatchRunningWorkoutStep(
            id: UUID(), title: "4 minute interval", measure: .time,
            distanceMeters: nil, durationSeconds: 240,
            intensityText: nil, phase: "interval"
        )
        let recovery = WatchRunningWorkoutStep(
            id: UUID(), title: "2 minute recovery", measure: .time,
            distanceMeters: nil, durationSeconds: 120,
            intensityText: nil, phase: "recovery"
        )
        let prepared = ATHLTHRunningWorkoutAppendPolicy
            .stepsAfterExistingFreeRun([warmup, interval, recovery])
        XCTAssertEqual(prepared.map(\.phase), ["interval", "recovery"])
        XCTAssertTrue(ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: false,
            startNow: false,
            steps: prepared
        ))
        let free = ATHLTHRunningWorkoutAppendPolicy.freeRunningStage()
        XCTAssertEqual(free.measure, .open)
        XCTAssertEqual(free.phase, "free")
        XCTAssertFalse(ATHLTHRunningStepEngine.isCompleted(
            step: free, elapsedTime: 3600, distanceMeters: 13000,
            stepStartElapsedTime: 0, stepStartDistanceMeters: 0
        ), "Free stage must never auto-start the queued interval")
    }

    func testQueueOnlyAllowedWhenProgramAlreadyInProgress() {
        let interval = step()
        XCTAssertTrue(ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: true,
            startNow: false,
            steps: [interval]
        ))
        XCTAssertFalse(ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: true,
            startNow: true,
            steps: [interval]
        ))
        XCTAssertEqual(
            ATHLTHRunningWorkoutAppendPolicy
                .stepsAfterExistingFreeRun([interval]).count,
            1
        )
        XCTAssertTrue(
            ATHLTHRunningWorkoutAppendPolicy
                .stepsAfterExistingFreeRun([step(
                    measure: .time, seconds: 600
                )]).count == 1
        )
    }

}
