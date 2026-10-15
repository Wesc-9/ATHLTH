import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutDurationEstimatorTests: XCTestCase {
    func testStrengthSetsAndRestProduceUsableApproximation() {
        var strength = block(.exercise, "Squat", reps: 10)
        strength.setCount = 3
        strength.restBetweenSetsSeconds = 90

        // Three 10-rep sets with two recovery periods.
        XCTAssertEqual(
            ATHLTHWorkoutDurationEstimator.minutes(for: [strength]), 10
        )
    }

    func testWarmupIntervalsAndCooldownIncludeExplicitRest() {
        var warmup = block(.run, "Warm-up", seconds: 300)
        warmup.phase = .warmup
        let pause = block(.rest, "Recovery", seconds: 120)
        var cooldown = block(.run, "Cool-down", seconds: 300)
        cooldown.phase = .cooldown

        XCTAssertEqual(
            ATHLTHWorkoutDurationEstimator.minutes(
                for: [warmup, pause, cooldown]
            ), 15
        )
    }

    func testUnknownRunningPaceDoesNotPretendToBeAccurate() {
        var run = block(.run, "Five kilometers")
        run.distanceMeters = 5_000
        XCTAssertNil(ATHLTHWorkoutDurationEstimator.minutes(for: [run]))
    }

    func testNotesOrRestWithoutTrainingAreNotAnExecutableEstimate() {
        XCTAssertNil(ATHLTHWorkoutDurationEstimator.minutes(for: []))
        XCTAssertNil(ATHLTHWorkoutDurationEstimator.minutes(
            for: [block(.rest, "Recovery", seconds: 90)]
        ))
    }

    private func block(
        _ kind: WorkoutTemplateBlockKind,
        _ name: String,
        reps: Int? = nil,
        seconds: Double? = nil
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1,
            kind: kind,
            title: name,
            exerciseSlug: nil,
            distanceMeters: nil,
            repetitions: reps,
            durationSeconds: seconds,
            targetWeightKilograms: nil,
            loadNote: nil,
            notes: nil
        )
    }
}
