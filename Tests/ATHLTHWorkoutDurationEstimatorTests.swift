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

    func testCyclingIsTimedActivityAndDoesNotInventDistance() {
        var cycling = block(.note, "Cycling", seconds: 1800)
        cycling.activityTag = "cycling"
        XCTAssertEqual(ATHLTHWorkoutDurationEstimator.minutes(for: [cycling]), 30)
        XCTAssertTrue(ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Cycling", kind: .custom,
            durationMinutes: 30, routeID: nil, blocks: [cycling]
        ).isValid)
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
    func testMixedWarmupMainCooldownCountsAllSpecifiedTimeAndPauses() {
        var warmCycling = block(.note, "Bike warm-up", seconds: 600)
        warmCycling.activityTag = "cycling"
        warmCycling.phase = .warmup
        var warmMobility = block(.exercise, "Warm-up mobility", seconds: 300)
        warmMobility.phase = .warmup
        var mainStrength = block(.exercise, "Strength", seconds: 1_200)
        mainStrength.phase = .main
        var runIntervals = block(.run, "Four running intervals", seconds: 240)
        runIntervals.phase = .main
        runIntervals.groupRounds = 4
        runIntervals.groupKind = .intervals
        runIntervals.groupID = UUID()
        var rest = block(.rest, "Recovery", seconds: 120)
        rest.phase = .main
        var walk = block(.run, "Walk down", seconds: 300)
        walk.phase = .cooldown
        var stretch = block(.exercise, "Stretch", seconds: 300)
        stretch.phase = .cooldown

        // The expanded runtime recipe is authoritative. Repetitions are
        // represented here as independent work/rest steps to test totals
        // without relying on editor-specific interval-group serialization.
        let timeline = [
            warmCycling, warmMobility, mainStrength,
            runIntervals, rest, runIntervals, rest,
            runIntervals, rest, runIntervals,
            walk, stretch
        ].map { step -> WorkoutTemplateBlock in
            var copy = step
            // These represent the four actual work steps, not four groups.
            copy.groupRounds = nil
            copy.groupKind = nil
            copy.groupID = nil
            return copy
        }
        // 10+5 warmup, 20 strength, 4x4 run + 3x2 pause, 5+5 cooldown
        // = 67 min, rounded to the planner's nearest upper 5-min bucket.
        XCTAssertEqual(ATHLTHWorkoutDurationEstimator.minutes(for: timeline), 70)
    }

    func testUnspecifiedCyclingAndRestDoNotUndercountWorkout() {
        let run = block(.run, "Run", seconds: 600)
        var cycling = block(.note, "Bike")
        cycling.activityTag = "cycling"
        XCTAssertNil(ATHLTHWorkoutDurationEstimator.minutes(for: [run, cycling]))

        let untimedRest = block(.rest, "Open-ended rest")
        XCTAssertNil(ATHLTHWorkoutDurationEstimator.minutes(
            for: [run, untimedRest]
        ))
    }

    func testInvalidOrOverLimitDurationsAreNotFakedAsFourHours() {
        XCTAssertNil(ATHLTHWorkoutDurationEstimator.minutes(
            for: [block(.run, "Infinite duration", seconds: .infinity)]
        ))
        XCTAssertNil(ATHLTHWorkoutDurationEstimator.minutes(
            for: [block(.run, "Five hour run", seconds: 18_000)]
        ))
    }

}
