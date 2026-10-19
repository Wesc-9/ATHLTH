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

    func testFourByFourDistanceUsesEveryIndividualSpeedAndThreeRecoveries() {
        func pace(_ speed: Double) -> RunningIntensityTarget {
            RunningIntensityTarget(
                kind: .pace,
                paceMinSecondsPerKilometer: 3_600 / speed,
                paceMaxSecondsPerKilometer: 3_600 / speed,
                heartRateZone: nil, rpe: nil
            )
        }
        let warmup = RunningWorkoutBlock(
            kind: .warmup, title: "Oppvarming",
            work: .time(600, intensity: pace(10))
        )
        let effort = RunningWorkoutBlock(
            kind: .work, title: "4 × 4", repetitions: 4,
            work: .time(240, intensity: pace(11)),
            recovery: .time(120, intensity: pace(6)),
            repetitionOverrides: (1...4).map { number in
                RunningRepetitionOverride(
                    repetition: number,
                    work: .time(240, intensity: pace(10 + Double(number) * 0.5))
                )
            }
        )
        let cooldown = RunningWorkoutBlock(
            kind: .cooldown, title: "Nedjogging",
            work: .time(600, intensity: pace(9))
        )
        let now = Date()
        let workout = RunningWorkoutTemplate(
            id: UUID(), title: "4 × 4 intervaller", type: .intervals,
            summary: "", blocks: [warmup, effort, cooldown],
            routeID: nil, isBuiltIn: false, createdAt: now, updatedAt: now
        )

        XCTAssertEqual(workout.estimatedDurationSeconds ?? 0, 2_520, accuracy: 0.1)
        // 10 min warmup at 10 + individual 4 min efforts at
        // 10.5/11/11.5/12 + three 2 min active rests at 6
        // + 10 min cooldown at 9 = ~6.77 km.
        XCTAssertEqual(workout.estimatedDistanceMeters ?? 0, 6_766.67,
                       accuracy: 0.5)
    }

    func testMissingPauseSpeedNeverInflatesDistance() {
        let pace = RunningIntensityTarget(
            kind: .pace, paceMinSecondsPerKilometer: 300,
            paceMaxSecondsPerKilometer: 300,
            heartRateZone: nil, rpe: nil
        )
        let intervals = RunningWorkoutBlock(
            kind: .work, title: "4 × 4", repetitions: 4,
            work: .time(240, intensity: pace),
            recovery: .time(120, intensity: .easy)
        )
        let date = Date()
        let template = RunningWorkoutTemplate(
            id: UUID(), title: "4 × 4", type: .intervals,
            summary: "", blocks: [intervals],
            routeID: nil, isBuiltIn: false, createdAt: date, updatedAt: date
        )
        XCTAssertNil(template.estimatedDistanceMeters)
        XCTAssertEqual(template.estimatedDurationSeconds ?? 0, 1_320,
                       accuracy: 0.1)
    }

    func testDistanceBasedTargetDerivesDurationFromSpeed() {
        let pace = RunningIntensityTarget(
            kind: .pace, paceMinSecondsPerKilometer: 300,
            paceMaxSecondsPerKilometer: 300,
            heartRateZone: nil, rpe: nil
        )
        XCTAssertEqual(
            ATHLTHRunningEstimate.durationSeconds(
                for: .distance(2_000, intensity: pace)
            ) ?? 0, 600, accuracy: 0.1
        )
        XCTAssertEqual(
            ATHLTHRunningEstimate.distanceMeters(
                for: .time(240, intensity: pace)
            ) ?? 0, 800, accuracy: 0.1
        )
    }

    func testRecipePreviewEstimateCountsRestWithSpeedAndRequiresFullTargets() {
        var work = block(.run, "Drag", seconds: 240)
        work.targetPaceSecondsPerKilometer = 300
        var pause = block(.rest, "Aktiv pause", seconds: 120)
        pause.targetPaceSecondsPerKilometer = 600
        XCTAssertEqual(
            ATHLTHRunningEstimate.distanceMeters(for: [work, pause]) ?? 0,
            1_000, accuracy: 0.1
        )
        pause.targetPaceSecondsPerKilometer = nil
        XCTAssertNil(ATHLTHRunningEstimate.distanceMeters(for: [work, pause]))
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
