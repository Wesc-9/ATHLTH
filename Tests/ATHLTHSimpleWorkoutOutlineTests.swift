import XCTest
@testable import ATHLTH

/// Simple/Advanced are two projections of the same real workout timeline.
/// Neither Plan Studio nor Quick Train may rewrite a recipe for presentation.
final class ATHLTHSimpleWorkoutOutlineTests: XCTestCase {
    private func block(
        _ title: String,
        kind: WorkoutTemplateBlockKind = .run,
        phase: WorkoutPhaseKind,
        index: Int,
        duration: TimeInterval = 60,
        pace: Double? = nil
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: index, kind: kind, title: title,
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: duration, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: phase,
            targetPaceSecondsPerKilometer: pace
        )
    }

    func testOneMinuteIntervalsCompactIntoSingleSimpleMainGroup() {
        var recipe = [
            block("Warm up", phase: .warmup, index: 1, duration: 600)
        ]
        for index in 1...12 {
            recipe.append(block(
                "1min VO2-maks", phase: .main,
                index: recipe.count + 1
            ))
            if index < 12 {
                recipe.append(block(
                    "Active recovery", kind: .rest,
                    phase: .recovery, index: recipe.count + 1
                ))
            }
        }
        recipe.append(block(
            "Cool down", phase: .cooldown,
            index: recipe.count + 1, duration: 480
        ))
        let untouched = recipe
        let stages = ATHLTHSimpleWorkoutOutline.stages(for: recipe)
        XCTAssertEqual(stages.count, 3)
        XCTAssertEqual(stages[1].phase, .main)
        XCTAssertEqual(stages[1].sourceStepCount, 23)
        XCTAssertEqual(stages[1].items.count, 1)
        XCTAssertEqual(stages[1].items[0].repetitions, 12)
        XCTAssertEqual(stages[1].items[0].representedSteps, 23)
        XCTAssertTrue(stages[1].items[0].title.contains("12 ×"))
        XCTAssertEqual(stages[1].plannedSeconds, 23 * 60)
        XCTAssertEqual(recipe, untouched)
    }

    func testPersonalTargetsMustNotBeHiddenByGroupingDistinctRepeats() {
        let recipe = [
            block("VO2", phase: .main, index: 1, pace: 300),
            block("Recovery", kind: .rest, phase: .recovery, index: 2),
            block("VO2", phase: .main, index: 3, pace: 275),
            block("Recovery", kind: .rest, phase: .recovery, index: 4)
        ]
        let items = ATHLTHSimpleWorkoutOutline.stages(for: recipe)[0].items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.representedSteps), [2, 2])
    }

    func testCompactModeNeverChangesSourceOrderOrSequence() {
        let recipe = [
            block("Warm up", phase: .warmup, index: 1, duration: 300),
            block("Work", phase: .main, index: 2, duration: 120),
            block("Recovery", kind: .rest, phase: .recovery, index: 3),
            block("Cool down", phase: .cooldown, index: 4, duration: 300)
        ]
        let before = recipe.map(\.sequence)
        _ = ATHLTHSimpleWorkoutOutline.stages(for: recipe)
        XCTAssertEqual(recipe.map(\.sequence), before)
        XCTAssertEqual(recipe.count, 4)
    }
    func testBasicRemoveOneExerciseKeepsOtherExercisesAndOrder() {
        let a = block("Squat", kind: .exercise, phase: .main, index: 1)
        let b = block("Press", kind: .exercise, phase: .main, index: 2)
        let c = block("Deadlift", kind: .exercise, phase: .main, index: 3)
        let original = [a, b, c]
        let result = ATHLTHBasicWorkoutContentsPolicy.removing(
            from: original, startingAt: 1, representedSteps: 1
        )
        XCTAssertEqual(result.map(\.title), ["Squat", "Deadlift"])
        XCTAssertEqual(original.count, 3, "Basic must not mutate saved source")
    }

    func testBasicRemoveCompactIntervalRemovesWholeGroupSafely() {
        let group = UUID()
        var effort = block("4 minutes", phase: .main, index: 1)
        effort.groupID = group
        var rest = block(
            "2 minutes", kind: .rest, phase: .recovery, index: 2
        )
        rest.groupID = group
        let next = block("Cool down", phase: .cooldown, index: 3)
        let original = [effort, rest, next]
        let result = ATHLTHBasicWorkoutContentsPolicy.removing(
            from: original, startingAt: 0, representedSteps: 1
        )
        XCTAssertEqual(result.map(\.title), ["Cool down"],
            "Never keep half an imported interval or superset group")
        XCTAssertEqual(original.count, 3)
    }

    func testBasicRemoveRejectsInvalidIndicesWithoutDataLoss() {
        let original = [block("Run", phase: .main, index: 1)]
        XCTAssertEqual(
            ATHLTHBasicWorkoutContentsPolicy.removing(
                from: original, startingAt: -1, representedSteps: 1
            ),
            original
        )
        XCTAssertEqual(
            ATHLTHBasicWorkoutContentsPolicy.removing(
                from: original, startingAt: 0, representedSteps: 0
            ),
            original
        )
    }


    func testBasicFreeRunIsOneUntargetedOriginalBlock() {
        let free = ATHLTHBasicFreeRunPolicy.makeOpenRunningBlock()
        XCTAssertTrue(ATHLTHBasicFreeRunPolicy.isFreeRunning([free]))
        XCTAssertEqual(free.kind, .run)
        XCTAssertNil(free.durationSeconds)
        XCTAssertNil(free.distanceMeters)
        XCTAssertNil(free.targetPaceSecondsPerKilometer)
        XCTAssertNil(ATHLTHWorkoutDurationEstimator.minutes(for: [free]),
                     "Do not fabricate a 30-minute training goal")
        let steps = PlannedWorkoutWatchBuilder.runningStepsFromEditedBlocks([free])
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps.first?.measure, .open,
                       "Watch running must wait for the user's own finish")
    }

    func testBasicFreeRunCalendarEstimateDoesNotBecomeRunningTarget() {
        let free = ATHLTHBasicFreeRunPolicy.makeOpenRunningBlock()
        let minutes = ATHLTHBasicFreeRunPolicy.scheduledMinutes(
            blocks: [free], requestedMinutes: nil, basicFreeRunning: true
        )
        XCTAssertEqual(minutes, 30)
        XCTAssertNil(free.durationSeconds)
        XCTAssertTrue(ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Free run", kind: .running,
            durationMinutes: minutes ?? 30, routeID: nil, blocks: [free]
        ).isValid, "Free running must also save inside a structured training plan")
        XCTAssertEqual(ATHLTHBasicFreeRunPolicy.scheduledMinutes(
            blocks: [free], requestedMinutes: nil, basicFreeRunning: false
        ), nil)
    }

    func testBasicFreeRunMustNotMisidentifyTargetedOrMultiStepRuns() {
        let free = ATHLTHBasicFreeRunPolicy.makeOpenRunningBlock()
        var targeted = free
        targeted.durationSeconds = 1_200
        XCTAssertFalse(ATHLTHBasicFreeRunPolicy.isFreeRunning([targeted]))
        var distance = free
        distance.distanceMeters = 5_000
        XCTAssertFalse(ATHLTHBasicFreeRunPolicy.isFreeRunning([distance]))
        var paced = free
        paced.targetPaceSecondsPerKilometer = 300
        XCTAssertFalse(ATHLTHBasicFreeRunPolicy.isFreeRunning([paced]))
        XCTAssertFalse(ATHLTHBasicFreeRunPolicy.isFreeRunning([free, free]))
        XCTAssertFalse(ATHLTHBasicFreeRunPolicy.isFreeRunning([]))
        XCTAssertNil(ATHLTHBasicFreeRunPolicy.scheduledMinutes(
            blocks: [targeted], requestedMinutes: nil, basicFreeRunning: true
        ))
    }


    func testBasicRouteUsesSameFreeRunInsteadOfAppendingSecondRun() {
        let original = ATHLTHBasicFreeRunPolicy.makeOpenRunningBlock()
        let id = UUID()
        let attached = ATHLTHBasicWorkoutRoutePolicy.attachingToOpenRun(
            routeID: id, distanceMeters: 5300,
            in: [original]
        )
        XCTAssertEqual(attached?.count, 1)
        XCTAssertEqual(attached?.first?.routeID, id)
        XCTAssertNil(attached?.first?.distanceMeters,
                     "A route must not convert free running into a distance target")
        XCTAssertEqual(attached?.first?.title, original.title)
        XCTAssertEqual(attached?.first?.editorDragID, original.editorDragID)
        XCTAssertNil(ATHLTHBasicWorkoutRoutePolicy.attachingToOpenRun(
            routeID: id, distanceMeters: .nan,
            in: [original]
        ))
    }

    func testRemovingRouteNeverDeletesWorkoutStepsOrTargets() {
        let routeID = UUID()
        var routedRun = block("Run", phase: .main, index: 1)
        routedRun.routeID = routeID
        routedRun.distanceMeters = 5000
        let strength = block(
            "Squats", kind: .exercise, phase: .main, index: 2
        )
        let before = [routedRun, strength]
        let after = ATHLTHBasicWorkoutRoutePolicy.clearingRoute(
            routeID, in: before
        )
        XCTAssertEqual(after.count, 2)
        XCTAssertNil(after[0].routeID)
        XCTAssertEqual(after[0].distanceMeters, 5000)
        XCTAssertEqual(after[1], strength)
        XCTAssertEqual(before[0].routeID, routeID,
                       "Never mutate original recipe while previewing")
    }

    func testRemovingExerciseDoesNotUnselectUnrelatedGlobalRoute() {
        let selectedID = UUID()
        let exercise = block(
            "Squats", kind: .exercise, phase: .main, index: 1
        )
        let after = ATHLTHBasicWorkoutContentsPolicy.removing(
            from: [exercise], startingAt: 0, representedSteps: 1
        )
        XCTAssertFalse(ATHLTHBasicWorkoutRoutePolicy.shouldClearSelectedRoute(
            routeID: selectedID, before: [exercise], after: after
        ))
        var routed = block("Run", phase: .main, index: 1)
        routed.routeID = selectedID
        XCTAssertTrue(ATHLTHBasicWorkoutRoutePolicy.shouldClearSelectedRoute(
            routeID: selectedID, before: [routed], after: []
        ))
    }

    func testBasicRestoresSingleStructuredRunningStepAsStructured() {
        var oneInterval = ATHLTHBasicFreeRunPolicy.makeOpenRunningBlock()
        oneInterval.title = "4-minute interval"
        oneInterval.durationSeconds = 240
        XCTAssertEqual(
            ATHLTHBasicFreeRunPolicy.initialMode(
                blocks: [oneInterval], routeID: nil
            ).rawValue,
            RunQuickStartMode.structured.rawValue
        )
        XCTAssertEqual(
            ATHLTHBasicFreeRunPolicy.initialMode(
                blocks: [ATHLTHBasicFreeRunPolicy.makeOpenRunningBlock()],
                routeID: nil
            ).rawValue,
            RunQuickStartMode.free.rawValue
        )
        XCTAssertEqual(
            ATHLTHBasicFreeRunPolicy.initialMode(
                blocks: [], routeID: UUID()
            ).rawValue,
            RunQuickStartMode.route.rawValue
        )
    }

    func testBasicNeverSilentlyReplacesCustomOpenEndedRunningExercise() {
        let free = ATHLTHBasicFreeRunPolicy.makeOpenRunningBlock()
        var named = free
        named.title = "My long slow run"
        XCTAssertFalse(ATHLTHBasicFreeRunPolicy.isFreeRunning([named]))
        var routed = free
        routed.routeID = UUID()
        XCTAssertTrue(ATHLTHBasicFreeRunPolicy.isFreeRunning([routed]),
                      "Navigation alone cannot make Free Run a target workout")
        var annotated = free
        annotated.notes = "Stay at easy effort and check form"
        XCTAssertFalse(ATHLTHBasicFreeRunPolicy.isFreeRunning([annotated]))
        var strength = free
        strength.kind = .exercise
        XCTAssertFalse(ATHLTHBasicFreeRunPolicy.isFreeRunning([strength]))
    }

    func testBasicSavedStrengthModesCannotEnterRunningComposer() {
        var strength = block(
            "Superset press", kind: .exercise,
            phase: .main, index: 1
        )
        strength.groupID = UUID()
        strength.groupKind = .superset
        XCTAssertFalse(ATHLTHStrengthModeAvailability.canImport(
            [strength], initialActivity: .running, containsStrength: false
        ))
        XCTAssertTrue(ATHLTHStrengthModeAvailability.canImport(
            [strength], initialActivity: .strength, containsStrength: false
        ))
    }

    func testBasicImportDeniesOtherSportsEvenWithoutStrengthGroups() {
        let run = block("Run", kind: .run, phase: .main, index: 1)
        let squat = block("Squat", kind: .exercise, phase: .main, index: 2)
        let rest = block("Rest", kind: .rest, phase: .recovery, index: 3)
        XCTAssertTrue(ATHLTHBasicWorkoutImportPolicy.accepts(
            blocks: [run, rest], initialActivity: .running
        ))
        XCTAssertTrue(ATHLTHBasicWorkoutImportPolicy.accepts(
            blocks: [squat, rest], initialActivity: .strength
        ))
        XCTAssertFalse(ATHLTHBasicWorkoutImportPolicy.accepts(
            blocks: [squat], initialActivity: .running
        ), "A plain strength exercise must not silently become a run")
        XCTAssertFalse(ATHLTHBasicWorkoutImportPolicy.accepts(
            blocks: [run, squat], initialActivity: .strength
        ), "Hybrid recipes belong in Advanced, not a one-tap Basic session")
    }

    func testRemovingRouteFromFreeRunLeavesOpenBlockUntargeted() {
        let original = ATHLTHBasicFreeRunPolicy.makeOpenRunningBlock()
        let id = UUID()
        let routed = ATHLTHBasicWorkoutRoutePolicy.attachingToOpenRun(
            routeID: id, distanceMeters: 3500, in: [original]
        )!
        let cleared = ATHLTHBasicWorkoutRoutePolicy.clearingRoute(
            id, in: routed
        )
        XCTAssertEqual(cleared.count, 1)
        XCTAssertEqual(cleared[0].editorDragID, original.editorDragID)
        XCTAssertTrue(ATHLTHBasicFreeRunPolicy.isFreeRunning(cleared),
                      "Free run should still be Free run after removing navigation")
        XCTAssertNil(cleared[0].durationSeconds)
        XCTAssertNil(cleared[0].distanceMeters)
    }

    func testBasicRoutedFreeRunSurvivesSaveAndReopenWithoutTarget() {
        let id = UUID()
        let free = ATHLTHBasicFreeRunPolicy.makeOpenRunningBlock()
        let routed = ATHLTHBasicWorkoutRoutePolicy.attachingToOpenRun(
            routeID: id, distanceMeters: 7_500, in: [free]
        )!
        XCTAssertTrue(ATHLTHBasicFreeRunPolicy.isFreeRunning(routed))
        XCTAssertEqual(
            ATHLTHBasicFreeRunPolicy.initialMode(blocks: routed, routeID: id),
            .free
        )
        XCTAssertEqual(ATHLTHBasicFreeRunPolicy.scheduledMinutes(
            blocks: routed, requestedMinutes: nil, basicFreeRunning: true
        ), 30, "A calendar estimate is allowed only outside the open run step")
        let steps = PlannedWorkoutWatchBuilder.runningStepsFromEditedBlocks(
            routed
        )
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps.first?.measure, .open)
        XCTAssertNil(steps.first?.distanceMeters)
        XCTAssertNil(steps.first?.durationSeconds)
    }

    func testBasicOneTapActivitiesKeepTheirOriginalSport() {
        let expected: [(ATHLTHPlannedWorkoutType, ATHLTHWorkoutSportMode, Int)] = [
            (.walking, .walking, 30),
            (.cycling, .cycling, 30),
            (.mobility, .yoga, 15)
        ]
        for (type, expectedSport, minutes) in expected {
            let created = ATHLTHBasicWorkoutQuickStepPolicy.makeStep(
                for: type
            )
            XCTAssertNotNil(created)
            guard let created else { continue }
            XCTAssertEqual(ATHLTHWorkoutSportMode.forBlock(created),
                           expectedSport)
            XCTAssertEqual(created.durationSeconds, Double(minutes * 60))
            XCTAssertEqual(created.resolvedPhase, .main)
            XCTAssertNil(created.exerciseID,
                         "Quick activity cannot invent a library exercise ID")
            XCTAssertNil(created.groupID)
        }
        XCTAssertNil(ATHLTHBasicWorkoutQuickStepPolicy.makeStep(for: .running))
        XCTAssertNil(ATHLTHBasicWorkoutQuickStepPolicy.makeStep(for: .strength))
    }

    func testRestoredBasicModeUsesActualRecipeNotOldDraftLabel() {
        let open = ATHLTHBasicFreeRunPolicy.makeOpenRunningBlock()
        var timed = open
        timed.durationSeconds = 600
        XCTAssertEqual(
            ATHLTHBasicFreeRunPolicy.restoredMode(
                blocks: [timed], routeID: nil, previouslySelected: .free
            ).rawValue,
            RunQuickStartMode.structured.rawValue
        )
        XCTAssertEqual(
            ATHLTHBasicFreeRunPolicy.restoredMode(
                blocks: [open], routeID: UUID(),
                previouslySelected: .route
            ).rawValue,
            RunQuickStartMode.free.rawValue
        )
        XCTAssertEqual(
            ATHLTHBasicFreeRunPolicy.restoredMode(
                blocks: [], routeID: nil, previouslySelected: .structured
            ).rawValue,
            RunQuickStartMode.structured.rawValue
        )
    }

}
