import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHUnifiedActivityProfileTests: XCTestCase {
    private func block(
        _ kind: WorkoutTemplateBlockKind,
        sequence: Int = 1
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: sequence, kind: kind, title: "Recorded step",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 300, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )
    }

    private func workout(
        kind: WorkoutKind = .custom,
        category: String? = nil,
        blocks: [WorkoutTemplateBlock] = []
    ) -> PlannedSession {
        var plan = PlannedSession(
            id: UUID(), title: "Source", kind: kind,
            scheduledStart: nil, durationMinutes: 30,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: nil
        )
        plan.workoutCategory = category
        plan.workoutBlocks = blocks.isEmpty ? nil : blocks
        return plan
    }

    func testRunningPlusMobilityIsHybridInEveryPlanner() {
        let run = block(.run)
        var yoga = block(.note, sequence: 2)
        yoga.wellnessKind = .yoga
        let steps = [run, yoga]
        let profile = ATHLTHUnifiedActivityProfile(blocks: steps)
        XCTAssertEqual(profile.category, "hybrid")
        XCTAssertEqual(profile.workoutKind, .custom)

        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Run + Yoga", kind: .running,
            durationMinutes: 30, routeID: nil, blocks: steps
        )
        XCTAssertEqual(blueprint.category, "hybrid")
        let saved = blueprint.applying(to: nil)
        XCTAssertEqual(saved.workoutCategory, "hybrid")
        XCTAssertEqual(saved.kind, .custom)
        XCTAssertTrue(ATHLTHPlanWorkoutActivityFilter.hybrid.matches(saved))
        XCTAssertFalse(ATHLTHPlanWorkoutActivityFilter.running.matches(saved))
        XCTAssertEqual(ATHLTHPlannedWorkoutType.from(saved), .custom)
        XCTAssertEqual(saved.resolvedWorkoutBlocks.map(\.id), steps.map(\.id))
    }

    func testWalkingRecoveryWithinRunningIsNotSecondWorkoutActivity() {
        let run = block(.run)
        var recovery = block(.run, sequence: 2)
        recovery.cardioActivity = .walking
        recovery.activityTag = "active_recovery"
        let profile = ATHLTHUnifiedActivityProfile(blocks: [run, recovery])
        XCTAssertEqual(profile.category, "running")
        XCTAssertEqual(profile.workoutKind, .running)
    }

    func testUntaggedLegacyWalkingIsStillWalking() {
        let plan = workout(kind: .walking, blocks: [block(.run)])
        XCTAssertEqual(ATHLTHUnifiedActivityProfile.category(for: plan), "walking")
        XCTAssertTrue(ATHLTHPlanWorkoutActivityFilter.walking.matches(plan))
    }

    func testCyclingStrengthMixCannotMasqueradeAsStrengthOnly() throws {
        var cycle = block(.note)
        cycle.activityTag = "cycling"
        let plan = workout(kind: .strength, blocks: [cycle, block(.exercise, sequence: 2)])
        XCTAssertEqual(ATHLTHUnifiedActivityProfile.category(for: plan), "hybrid")
        XCTAssertTrue(ATHLTHPlanWorkoutActivityFilter.hybrid.matches(plan))
        XCTAssertEqual(ATHLTHPlannedWorkoutType.from(plan), .custom)
        XCTAssertEqual(ATHLTHLiveWorkoutEngineRouter.engine(for: cycle), .cycling)
    }

    func testPureCyclingKeepsCategoryButDoesNotInventCapture() throws {
        var cycle = block(.note)
        cycle.activityTag = "cycling"
        let profile = ATHLTHUnifiedActivityProfile(blocks: [cycle])
        XCTAssertEqual(profile.category, "cycling")
        XCTAssertEqual(profile.workoutKind, .custom)
        let saved = workout(kind: .custom, category: "cycling")
        XCTAssertEqual(ATHLTHUnifiedActivityProfile.category(for: saved), "cycling")
        XCTAssertEqual(ATHLTHPlannedWorkoutType.from(saved), .cycling)

        let timeline = ATHLTHUnifiedWorkout.editorBlocks(from: saved)
        XCTAssertEqual(timeline.count, 1)
        XCTAssertEqual(timeline.first?.activityTag, "cycling")
        XCTAssertEqual(timeline.first?.durationSeconds, 1800)
        XCTAssertEqual(timeline.first?.distanceMeters, nil)
    }

    func testMeditationAndYogaKeepDistinctPlanCategories() {
        var meditation = block(.note)
        meditation.wellnessKind = .meditation
        var yoga = block(.note)
        yoga.wellnessKind = .yoga
        let meditationProfile = ATHLTHUnifiedActivityProfile(blocks: [meditation])
        let yogaProfile = ATHLTHUnifiedActivityProfile(blocks: [yoga])
        XCTAssertEqual(meditationProfile.category, "recovery")
        XCTAssertEqual(meditationProfile.workoutKind, .recovery)
        XCTAssertEqual(yogaProfile.category, "mobility")
        XCTAssertEqual(yogaProfile.workoutKind, .mobility)
        XCTAssertEqual(ATHLTHUnifiedActivityProfile(
            blocks: [meditation, yoga]
        ).category, "mobility")

        let meditationTimeline = ATHLTHUnifiedWorkout.editorBlocks(
            from: workout(kind: .recovery, category: "meditation")
        )
        XCTAssertEqual(meditationTimeline.first?.wellnessKind, .meditation)
        XCTAssertEqual(meditationTimeline.first?.durationSeconds, 1800)
    }

    func testSimpleTimedCyclingYogaAndMeditationUseExistingStructuredPlayer() throws {
        for (category, kind) in [
            ("cycling", WorkoutKind.custom),
            ("yoga", WorkoutKind.mobility),
            ("meditation", WorkoutKind.recovery)
        ] {
            let source = workout(kind: kind, category: category)
            XCTAssertNil(source.workoutBlocks)
            let projected = try XCTUnwrap(
                ATHLTHUnifiedWorkout.timedNonCardioProjection(from: source)
            )
            XCTAssertEqual(projected.id, source.id)
            XCTAssertEqual(projected.kind, source.kind)
            XCTAssertEqual(projected.workoutBlocks?.count, 1)
            XCTAssertEqual(projected.workoutBlocks?.first?.durationSeconds, 1_800)
            XCTAssertNil(projected.workoutBlocks?.first?.distanceMeters)
            XCTAssertNil(projected.workoutBlocks?.first?.targetPaceSecondsPerKilometer)
            XCTAssertEqual(ATHLTHLiveWorkoutEngineRouter.engine(
                for: try XCTUnwrap(projected.workoutBlocks?.first)
            ), category == "cycling" ? .cycling : .mobility)
            // Projection is read-only. The original JSON is not migrated.
            XCTAssertNil(source.workoutBlocks)
        }
    }

    func testSimpleNonTimedCustomAndRunningDoNotGetFakeSteps() {
        let running = workout(kind: .running)
        let custom = workout(kind: .custom)
        XCTAssertNil(ATHLTHUnifiedWorkout.timedNonCardioProjection(from: running))
        XCTAssertNil(ATHLTHUnifiedWorkout.timedNonCardioProjection(from: custom))
    }

    func testLegacyExplicitCategoriesAndOriginalIdentitySurviveEncoding() throws {
        let old = workout(kind: .custom, category: "hiking")
        XCTAssertEqual(ATHLTHUnifiedActivityProfile.category(for: old), "walking")
        let oldCycling = workout(kind: .custom, category: "cycling")
        let recovered = try JSONDecoder().decode(
            PlannedSession.self, from: JSONEncoder().encode(oldCycling)
        )
        XCTAssertEqual(recovered.id, oldCycling.id)
        XCTAssertEqual(recovered.workoutCategory, "cycling")
        XCTAssertEqual(ATHLTHPlannedWorkoutType.from(recovered), .cycling)
    }

    func testMixedPlanDoesNotGetDuplicateParallelExerciseGraph() {
        var cycle = block(.note)
        cycle.activityTag = "cycling"
        var plan = workout(kind: .strength)
        ATHLTHUnifiedWorkout.apply(
            blocks: [cycle, block(.exercise, sequence: 2)],
            title: "Bike and lift", routeID: nil,
            estimatedMinutes: 25, to: &plan
        )
        XCTAssertEqual(plan.workoutCategory, "hybrid")
        XCTAssertEqual(plan.kind, .custom)
        XCTAssertTrue(plan.exercises.isEmpty)
        XCTAssertNil(plan.runningWorkout)
        XCTAssertNil(plan.runningWorkouts)
        XCTAssertEqual(plan.workoutBlocks?.count, 2)
    }
}
