import XCTest
@testable import ATHLTH

final class ATHLTHAlwaysOnFocusTests: XCTestCase {
    func testStrengthRepsArePrimaryForWorkingSet() {
        XCTAssertEqual(
            ATHLTHAlwaysOnFocusResolver.resolve(
                .init(kind: .strength, hasStrengthSession: true)
            ),
            .strengthReps
        )
    }

    func testRestOverridesTimedStrengthTarget() {
        XCTAssertEqual(
            ATHLTHAlwaysOnFocusResolver.resolve(
                .init(
                    kind: .strength,
                    hasStrengthSession: true,
                    isStrengthResting: true,
                    isTimedStrengthSet: true
                )
            ),
            .strengthRest
        )
    }

    func testFinishedExerciseDoesNotShowOldRepsAsCurrent() {
        XCTAssertEqual(
            ATHLTHAlwaysOnFocusResolver.resolve(
                .init(
                    kind: .strength,
                    hasStrengthSession: true,
                    isStrengthExerciseComplete: true
                )
            ),
            .strengthComplete
        )
    }

    func testTimedStrengthSetIsNotMistakenForReps() {
        XCTAssertEqual(
            ATHLTHAlwaysOnFocusResolver.resolve(
                .init(
                    kind: .strength,
                    hasStrengthSession: true,
                    isTimedStrengthSet: true
                )
            ),
            .strengthTime
        )
    }

    func testTimedIntervalGetsPriorityOverPace() {
        XCTAssertEqual(
            ATHLTHAlwaysOnFocusResolver.resolve(
                .init(
                    kind: .running,
                    currentRunningStepMeasure: .time
                )
            ),
            .intervalTime
        )
    }

    func testDistanceIntervalGetsPriorityOverPace() {
        XCTAssertEqual(
            ATHLTHAlwaysOnFocusResolver.resolve(
                .init(
                    kind: .running,
                    currentRunningStepMeasure: .distance
                )
            ),
            .intervalDistance
        )
    }

    func testOpenIntervalCannotInventRemainingTime() {
        XCTAssertEqual(
            ATHLTHAlwaysOnFocusResolver.resolve(
                .init(
                    kind: .running,
                    currentRunningStepMeasure: .open
                )
            ),
            .intervalOpen
        )
    }

    func testFreeRunPrioritizesPaceAndWalkingPrioritizesDistance() {
        XCTAssertEqual(
            ATHLTHAlwaysOnFocusResolver.resolve(
                .init(kind: .running)
            ),
            .paceAndDistance
        )
        XCTAssertEqual(
            ATHLTHAlwaysOnFocusResolver.resolve(
                .init(kind: .walking)
            ),
            .distanceAndPace
        )
    }

    func testGenericWorkoutDoesNotInventRunningMetrics() {
        for kind: WatchWorkoutKind in [
            .cycling, .hiit, .rowing, .functional, .stairClimbing, .yoga, .other
        ] {
            XCTAssertEqual(
                ATHLTHAlwaysOnFocusResolver.resolve(
                    .init(kind: kind)
                ),
                .elapsed
            )
        }
    }

    func testIntervalRenderingUsesSameSourceAsInteractiveView() {
        let step = WatchRunningWorkoutStep(
            id: UUID(),
            title: "4 minute effort",
            measure: .time,
            distanceMeters: nil,
            durationSeconds: 240,
            intensityText: nil
        )
        let readout = ATHLTHRunIntervalReadout.resolve(
            step: step,
            elapsedSeconds: 150,
            distanceMeters: 650
        )
        XCTAssertEqual(readout.remaining ?? -1, 90, accuracy: 0.001)
        XCTAssertEqual(readout.progress ?? -1, 0.625, accuracy: 0.001)
    }
}
