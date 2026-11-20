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

    func testActualYogaAndMeditationBlocksKeepTheirLiveSportIdentity() {
        var yoga = block(.note)
        yoga.wellnessKind = .yoga
        var meditation = block(.note, sequence: 2)
        meditation.wellnessKind = .meditation

        XCTAssertEqual(ATHLTHWorkoutSportMode.forBlock(yoga), .yoga)
        XCTAssertEqual(ATHLTHWorkoutSportMode.forBlock(meditation), .meditation)
        XCTAssertEqual(ATHLTHLiveWorkoutEngineRouter.engine(for: yoga), .mobility)
        XCTAssertEqual(ATHLTHLiveWorkoutEngineRouter.engine(for: meditation), .mobility)
        // The overall plan classification can still group wellness
        // activities together without overwriting each active sport.
        XCTAssertEqual(
            ATHLTHUnifiedActivityProfile(blocks: [yoga, meditation]).category,
            "mobility"
        )
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

    func testTaggedSportsShareUnifiedClassificationAndLiveRouter() {
        let kinds: [(String, String, ATHLTHLiveWorkoutEngine)] = [
            ("cycling", "cycling", .cycling),
            ("rowing", "rowing", .endurance),
            ("stairClimber", "stairclimber", .endurance),
            ("HIIT", "hiit", .instructions),
            ("circuit", "circuit", .instructions),
            ("functional", "functional", .instructions),
            ("sports", "sports", .instructions),
            ("yoga", "mobility", .mobility),
            ("mobility", "mobility", .mobility)
        ]
        for (tag, category, engine) in kinds {
            var note = block(.note)
            note.activityTag = tag
            let saved = workout(kind: .custom, blocks: [note])
            XCTAssertEqual(ATHLTHUnifiedActivityProfile.category(for: saved),
                category, "Wrong activity tag: \(tag)")
            XCTAssertEqual(ATHLTHLiveWorkoutEngineRouter.engine(for: note),
                engine, "Wrong live engine: \(tag)")
            XCTAssertEqual(saved.resolvedWorkoutBlocks.first?.id, note.id)
        }
    }

    func testTwoDifferentTaggedActivitiesStayOneHybridRecipe() {
        var rowing = block(.note)
        rowing.activityTag = "rowing"
        var cycling = block(.note, sequence: 2)
        cycling.activityTag = "cycling"
        let saved = workout(kind: .custom, blocks: [rowing, cycling])
        XCTAssertEqual(ATHLTHUnifiedActivityProfile.category(for: saved), "hybrid")
        XCTAssertEqual(saved.resolvedWorkoutBlocks.map(\.id), [rowing.id, cycling.id])

        var yoga = block(.note)
        yoga.activityTag = "yoga"
        yoga.wellnessKind = .yoga
        XCTAssertEqual(ATHLTHUnifiedActivityProfile(
            blocks: [yoga]
        ).category, "mobility", "A tagged yoga instruction is only one sport")
        let instruction = block(.note)
        XCTAssertEqual(ATHLTHUnifiedActivityProfile(
            blocks: [instruction], fallbackKind: .strength
        ).category, "strength")
    }


    func testEveryLegacyTimedSportCreatesOneSourcePreservingTimeline() throws {
        for category in [
            "cycling", "rowing", "stairclimber", "hiit", "circuit",
            "functional", "sports", "other", "yoga", "meditation",
            "mobility", "recovery"
        ] {
            let kind: WorkoutKind = category == "recovery" ||
                category == "meditation" ? .recovery :
                category == "yoga" || category == "mobility" ? .mobility :
                .custom
            let source = workout(kind: kind, category: category)
            let stableEncoder = JSONEncoder()
            stableEncoder.outputFormatting = [.sortedKeys]
            let before = try stableEncoder.encode(source)
            let projected = try XCTUnwrap(
                ATHLTHUnifiedWorkout.timedNonCardioProjection(from: source),
                "Missing iPhone-timed fallback for \(category)"
            )
            XCTAssertEqual(projected.id, source.id)
            XCTAssertEqual(projected.kind, source.kind)
            XCTAssertEqual(projected.workoutCategory, source.workoutCategory)
            XCTAssertEqual(projected.resolvedWorkoutBlocks.count, 1)
            XCTAssertEqual(projected.resolvedWorkoutBlocks[0].durationSeconds, 1800)
            XCTAssertNil(projected.resolvedWorkoutBlocks[0].distanceMeters)
            XCTAssertEqual(try stableEncoder.encode(source), before,
                "Projection must not rewrite the saved workout")
            XCTAssertEqual(ATHLTHUnifiedActivityProfile.category(for: projected),
                ATHLTHUnifiedActivityProfile.category(for: source))
        }
    }

    func testLegacyTimedProjectionRejectsMissingDurationAndUnsupportedKinds() {
        var bare = workout(kind: .custom, category: "cycling")
        bare.durationMinutes = nil
        XCTAssertNil(ATHLTHUnifiedWorkout.timedNonCardioProjection(from: bare))
        let running = workout(kind: .running, category: "running")
        XCTAssertNil(ATHLTHUnifiedWorkout.timedNonCardioProjection(from: running))
        let strength = workout(kind: .strength, category: "strength")
        XCTAssertNil(ATHLTHUnifiedWorkout.timedNonCardioProjection(from: strength))
    }


    func testUncategorizedLegacyWellnessAndStairAliasesStillRunOnIPhone() throws {
        let cases: [(WorkoutKind, String?, String)] = [
            (.mobility, nil, "mobility"),
            (.recovery, nil, "recovery"),
            (.custom, "mobility", "mobility"),
            (.custom, "stretching", "mobility"),
            (.custom, "stair_climbing", "stairclimber")
        ]
        for (kind, category, expected) in cases {
            let source = workout(kind: kind, category: category)
            let projected = try XCTUnwrap(
                ATHLTHUnifiedWorkout.timedNonCardioProjection(from: source),
                "Missing fallback for \(category ?? kind.title)"
            )
            XCTAssertEqual(projected.id, source.id)
            XCTAssertEqual(projected.workoutCategory, category)
            XCTAssertEqual(projected.resolvedWorkoutBlocks.count, 1)
            XCTAssertEqual(
                ATHLTHUnifiedActivityProfile.category(for: projected),
                expected
            )
            XCTAssertNil(projected.resolvedWorkoutBlocks.first?.distanceMeters)
        }
    }

}
