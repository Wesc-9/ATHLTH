import XCTest
@testable import ATHLTH

final class ATHLTHQuickRunTimelineAdapterTests: XCTestCase {
    private func block(
        _ name: String, kind: WorkoutTemplateBlockKind = .run,
        phase: WorkoutPhaseKind, seconds: Double
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: kind, title: name, exerciseSlug: nil,
            distanceMeters: nil, repetitions: nil, durationSeconds: seconds,
            targetWeightKilograms: nil, loadNote: nil, notes: nil, phase: phase
        )
    }

    private func workout(_ blocks: [WorkoutTemplateBlock]) -> PlannedSession {
        var session = PlannedSession(
            id: UUID(), title: "Intervals", kind: .running,
            scheduledStart: nil, durationMinutes: 30,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        session.workoutBlocks = blocks
        return session
    }

    func testSharedTimelinePreservesRunningPhases() {
        let warmup = block("Warm up", phase: .warmup, seconds: 600)
        var work = block("Work", phase: .main, seconds: 240)
        work.targetHeartRateZone = 4
        work.targetPaceSecondsPerKilometer = 270
        let rest = block("Rest", kind: .rest, phase: .recovery, seconds: 120)
        let source = workout([warmup, work, rest])
        let result = ATHLTHQuickRunTimelineAdapter.transfer(
            from: source, title: source.title,
            routeAlerts: .standard, autoPauseEnabled: true
        )
        XCTAssertEqual(result?.steps.map(\.phase), ["warmup", "work", "recovery"])
        XCTAssertEqual(result?.steps.map(\.durationSeconds), [600, 240, 120])
        XCTAssertEqual(result?.steps[1].targetHeartRateZone, 4)
        XCTAssertEqual(result?.steps[1].targetPaceMinSecondsPerKilometer, 270)
        XCTAssertEqual(result?.sourceWorkoutID, source.id)
    }

    func testIntervalRoundsUseSameExpansionAsPlan() {
        let id = UUID()
        var work = block("Fast", phase: .main, seconds: 240)
        work.groupID = id
        work.groupKind = .intervals
        work.groupRounds = 4
        var recovery = block("Jog", kind: .rest, phase: .recovery, seconds: 120)
        recovery.groupID = id
        recovery.groupKind = .intervals
        recovery.groupRounds = 4
        let transfer = ATHLTHQuickRunTimelineAdapter.transfer(
            from: workout([work, recovery]), title: "4 × 4",
            routeAlerts: .standard, autoPauseEnabled: false
        )
        XCTAssertEqual(transfer?.steps.filter { $0.phase == "work" }.count, 4)
        XCTAssertEqual(transfer?.steps.filter { $0.phase == "recovery" }.count, 3)
    }

    func testTimedStepsKeepAutomaticProgressionWhenAnotherStepIsOpen() {
        let timed = block("Timed run", phase: .main, seconds: 300)
        var open = block("Open run", phase: .main, seconds: 300)
        open.durationSeconds = nil
        let transfer = ATHLTHQuickRunTimelineAdapter.transfer(
            from: workout([timed, open]), title: "Free finale",
            routeAlerts: .standard, autoPauseEnabled: true
        )
        XCTAssertEqual(transfer?.steps[0].measure, .time)
        XCTAssertEqual(transfer?.steps[1].measure, .open)
        XCTAssertEqual(transfer?.autoAdvanceTimedSteps, true)
    }

    func testActiveJogRecoveryInMainPhaseIsNotAnIntervalEffort() {
        var warmup = block("Warm up", phase: .warmup, seconds: 300)
        warmup.cardioActivity = .running
        var effort = block("Fast", phase: .main, seconds: 180)
        effort.targetHeartRateZone = 4
        var jog = block("Jog recovery", phase: .main, seconds: 90)
        jog.activityTag = "active_recovery"
        jog.targetHeartRateZone = 1
        let source = workout([warmup, effort, jog])
        let transfer = ATHLTHQuickRunTimelineAdapter.transfer(
            from: source, title: source.title,
            routeAlerts: .standard, autoPauseEnabled: false
        )
        XCTAssertEqual(transfer?.steps.map(\.phase),
                       ["warmup", "work", "recovery"])
        XCTAssertEqual(transfer?.steps[2].targetHeartRateZone, 1)
        XCTAssertEqual(transfer?.steps[2].measure, .time)
    }

    func testPlannedIndoorRunRemainsIndoorAfterQuickStart() {
        var run = block("Indoor", phase: .main, seconds: 1_200)
        run.isIndoor = true
        var saved = workout([run])
        saved.workoutCategory = "indoor"
        XCTAssertEqual(RunEnvironment.forPlannedSession(saved), .indoor)
        XCTAssertEqual(ATHLTHQuickRunTimelineAdapter.environment(for: saved),
                       .indoor)
        saved = ATHLTHQuickRunTimelineAdapter.withEnvironment(
            saved, environment: .indoor
        )
        XCTAssertTrue(saved.resolvedWorkoutBlocks.allSatisfy {
            $0.kind != .run || $0.isIndoor == true
        })
        XCTAssertEqual(RunEnvironment.forPlannedSession(saved), .indoor)
        saved.workoutCategory = "treadmill"
        XCTAssertEqual(RunEnvironment.forPlannedSession(saved), .treadmill)
    }

    func testStrengthOrMixedWorkoutIsRejected() {
        let run = block("Run", phase: .main, seconds: 600)
        let strength = block("Strength", kind: .exercise, phase: .main, seconds: 60)
        XCTAssertNotNil(ATHLTHQuickRunTimelineAdapter.validationError(
            for: workout([run, strength])
        ))
    }

    func testAdvancedRunEnvironmentSelectionChangesLaunchRecipeWithoutMutatingSource() {
        let routeID = UUID()
        var run = block("Steady run", phase: .main, seconds: 1_200)
        run.routeID = routeID
        run.targetPaceSecondsPerKilometer = 330
        var original = workout([run])
        original.routeID = routeID

        let treadmill = ATHLTHQuickRunTimelineAdapter.withEnvironment(
            original, environment: .treadmill
        )
        XCTAssertEqual(treadmill.workoutCategory, "treadmill")
        XCTAssertNil(treadmill.routeID)
        XCTAssertEqual(treadmill.resolvedWorkoutBlocks.first?.isIndoor, true)
        XCTAssertEqual(treadmill.resolvedWorkoutBlocks.first?.treadmillInclinePercent, 0)
        XCTAssertNil(treadmill.resolvedWorkoutBlocks.first?.routeID)
        XCTAssertEqual(
            treadmill.resolvedWorkoutBlocks.first?.targetPaceSecondsPerKilometer,
            330
        )

        // Choosing the environment is not an in-place edit of a saved plan.
        XCTAssertEqual(original.routeID, routeID)
        XCTAssertEqual(original.resolvedWorkoutBlocks.first?.isIndoor, nil)
        XCTAssertEqual(original.resolvedWorkoutBlocks.first?.routeID, routeID)

        let outdoor = ATHLTHQuickRunTimelineAdapter.withEnvironment(
            treadmill, environment: .outdoor
        )
        XCTAssertEqual(outdoor.workoutCategory, "running")
        XCTAssertEqual(outdoor.resolvedWorkoutBlocks.first?.isIndoor, false)
        XCTAssertNil(outdoor.resolvedWorkoutBlocks.first?.treadmillInclinePercent)

        let indoor = ATHLTHQuickRunTimelineAdapter.withEnvironment(
            original, environment: .indoor
        )
        XCTAssertEqual(indoor.workoutCategory, "indoor")
        XCTAssertEqual(indoor.resolvedWorkoutBlocks.first?.isIndoor, true)
        XCTAssertNil(indoor.resolvedWorkoutBlocks.first?.treadmillInclinePercent)
        XCTAssertNil(indoor.routeID)
    }

    func testTreadmillChoicePreservesExistingIncline() {
        var run = block("Incline repeats", phase: .main, seconds: 240)
        run.isIndoor = true
        run.treadmillInclinePercent = 4
        let updated = ATHLTHQuickRunTimelineAdapter.withEnvironment(
            workout([run]), environment: .treadmill
        )
        XCTAssertEqual(updated.resolvedWorkoutBlocks.first?.treadmillInclinePercent, 4)
        XCTAssertNil(ATHLTHQuickRunTimelineAdapter.validationError(for: updated))
    }

    func testTreadmillSelectionUsesPlanMetadata() {
        var run = block("Treadmill", phase: .main, seconds: 600)
        run.isIndoor = true
        run.treadmillInclinePercent = 2
        XCTAssertEqual(
            ATHLTHQuickRunTimelineAdapter.environment(for: workout([run])),
            .treadmill
        )
    }
}
