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
        XCTAssertFalse(ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: false,
            startNow: false,
            steps: [step()]
        ))
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
}
