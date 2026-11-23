import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutPhasePlacementTests: XCTestCase {
    private func block(
        _ title: String,
        phase: WorkoutPhaseKind,
        group: UUID? = nil
    ) -> WorkoutTemplateBlock {
        var result = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: title, exerciseSlug: nil,
            distanceMeters: nil, repetitions: nil, durationSeconds: 600,
            targetWeightKilograms: nil, loadNote: nil, notes: nil,
            phase: phase
        )
        result.groupID = group
        return result
    }

    func testWarmupAddedBeforeMainAndCooldown() {
        let items = [block("Strength", phase: .main),
                     block("Cool down", phase: .cooldown)]
        XCTAssertEqual(ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: .warmup, in: items
        ), 0)
    }

    func testMainAddedBeforeCooldown() {
        let items = [block("Warm up", phase: .warmup),
                     block("Cool down", phase: .cooldown)]
        XCTAssertEqual(ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: .main, in: items
        ), 1)
    }

    func testAdditionalWarmupStaysAfterExistingWarmup() {
        let items = [block("First", phase: .warmup),
                     block("Main", phase: .main)]
        XCTAssertEqual(ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: .warmup, in: items
        ), 1)
    }

    func testGroupBoundaryIsNeverSplit() {
        let id = UUID()
        let items = [block("Work", phase: .main, group: id),
                     block("Rest", phase: .cooldown, group: id),
                     block("Finish", phase: .cooldown)]
        XCTAssertEqual(ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: .main, in: items
        ), 0)
    }

    func testCooldownAppendsAfterOtherPhases() {
        let items = [block("Main", phase: .main)]
        XCTAssertEqual(ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: .cooldown, in: items
        ), items.count)
    }
    func testWarmupPauseIsKeptBeforeMainWithoutASeparateRecoveryPhase() {
        var rest = block("Pause", phase: .warmup)
        rest.kind = .rest
        let items = [
            block("Easy cycling", phase: .warmup),
            block("Intervals", phase: .main),
            block("Cool down", phase: .cooldown)
        ]
        let index = ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: rest.resolvedPhase, in: items
        )
        XCTAssertEqual(rest.resolvedPhase, .warmup)
        XCTAssertEqual(index, 1)
    }

    func testCooldownPauseAppendsAfterMainEvenWhenKindIsRest() {
        var rest = block("Pause", phase: .cooldown)
        rest.kind = .rest
        let items = [
            block("Easy jog", phase: .warmup),
            block("Strength", phase: .main),
            block("Easy cycling", phase: .cooldown)
        ]
        XCTAssertEqual(ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: rest.resolvedPhase, in: items
        ), 3)
    }

    func testNewWarmupNeverSplitsAnIntervalGroup() {
        let groupID = UUID()
        let items = [
            block("Intervals", phase: .main, group: groupID),
            block("Interval rest", phase: .main, group: groupID),
            block("Cool down", phase: .cooldown)
        ]
        XCTAssertEqual(ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: .warmup, in: items
        ), 0)
    }


    func testFourByFourPausesStayBetweenIntervals() {
        func pause() -> WorkoutTemplateBlock {
            var item = block("Pause", phase: .recovery)
            item.kind = .rest
            item.durationSeconds = 120
            return item
        }
        let timeline = [
            block("Oppvarming", phase: .warmup),
            block("Intervall 1", phase: .main), pause(),
            block("Intervall 2", phase: .main), pause(),
            block("Intervall 3", phase: .main), pause(),
            block("Intervall 4", phase: .main),
            block("Nedjogging", phase: .cooldown)
        ]
        let sections = ATHLTHWorkoutTimelinePresentation.sections(for: timeline)
        XCTAssertEqual(sections.map(\.phase), [.warmup, .main, .cooldown])
        XCTAssertEqual(sections.map(\.activityCount), [1, 4, 1])
        XCTAssertEqual(sections[1].blocks.map(\.title), [
            "Intervall 1", "Pause", "Intervall 2", "Pause",
            "Intervall 3", "Pause", "Intervall 4"
        ])
        XCTAssertEqual(sections[2].blocks.map(\.title), ["Nedjogging"])
        XCTAssertEqual(sections.flatMap(\.blocks), timeline)
    }

    func testWarmupPauseAndNonRestRecoveryDoNotMove() {
        var pause = block("Pause etter oppvarming", phase: .recovery)
        pause.kind = .rest
        let timeline = [
            block("Oppvarming", phase: .warmup), pause,
            block("Intervall", phase: .main),
            block("Restitusjonsøvelse", phase: .recovery),
            block("Nedtrapping", phase: .cooldown)
        ]
        let sections = ATHLTHWorkoutTimelinePresentation.sections(for: timeline)
        XCTAssertEqual(sections.map(\.phase),
                       [.warmup, .main, .recovery, .cooldown])
        XCTAssertEqual(sections[0].blocks.map(\.title),
                       ["Oppvarming", "Pause etter oppvarming"])
        XCTAssertEqual(sections.flatMap(\.blocks), timeline)
    }

    func testSimpleSessionKeepsItsThreePhases() {
        let timeline = [
            block("Oppvarming", phase: .warmup),
            block("Intervall", phase: .main),
            block("Nedtrapping", phase: .cooldown)
        ]
        let sections = ATHLTHWorkoutTimelinePresentation.sections(for: timeline)
        XCTAssertEqual(sections.map(\.phase), [.warmup, .main, .cooldown])
        XCTAssertEqual(sections.map(\.activityCount), [1, 1, 1])
    }

    func testDeleteEntireWarmupCategoryRemovesAllItsSteps() {
        let original = [
            block("Warmup jog", phase: .warmup),
            block("Warmup strides", phase: .warmup),
            block("Main effort", phase: .main),
            block("Cool down", phase: .cooldown)
        ]
        let result = ATHLTHWorkoutPhaseDeletionPolicy.removing(
            .warmup, from: original, visiblePhases: [.warmup, .main, .cooldown]
        )
        XCTAssertEqual(result.map(\.title), ["Main effort", "Cool down"])
        XCTAssertEqual(result.map(\.sequence), [1, 2])
    }

    func testDeletingMainAlsoRemovesPausesDisplayedInsideMain() {
        var rest = block("Interval pause", phase: .recovery)
        rest.kind = .rest
        let original = [
            block("Warmup", phase: .warmup),
            block("Interval one", phase: .main), rest,
            block("Interval two", phase: .main),
            block("Cooldown", phase: .cooldown)
        ]
        XCTAssertEqual(
            ATHLTHWorkoutPhaseDeletionPolicy.presentedPhase(
                for: rest, visiblePhases: [.warmup, .main, .cooldown]
            ),
            .main
        )
        let remaining = ATHLTHWorkoutPhaseDeletionPolicy.removing(
            .main, from: original,
            visiblePhases: [.warmup, .main, .cooldown]
        )
        XCTAssertEqual(remaining.map(\.title), ["Warmup", "Cooldown"])
    }

    func testSeparateRecoveryCategoryRemainsWhenDeletingMain() {
        var rest = block("Recovery", phase: .recovery)
        rest.kind = .rest
        let remaining = ATHLTHWorkoutPhaseDeletionPolicy.removing(
            .main,
            from: [block("Main", phase: .main), rest],
            visiblePhases: [.main, .recovery]
        )
        XCTAssertEqual(remaining.map(\.title), ["Recovery"])
    }

    func testDeleteEmptyCategoryDoesNotModifyOtherSteps() {
        let original = [block("Main", phase: .main)]
        let result = ATHLTHWorkoutPhaseDeletionPolicy.removing(
            .warmup, from: original, visiblePhases: [.warmup, .main]
        )
        XCTAssertEqual(result.map(\.title), ["Main"])
    }

    func testDeleteCategoryClearsOrphanedIntervalGroup() {
        let group = UUID()
        let remaining = ATHLTHWorkoutPhaseDeletionPolicy.removing(
            .warmup,
            from: [
                block("Warmup interval", phase: .warmup, group: group),
                block("Main interval", phase: .main, group: group),
            ],
            visiblePhases: [.warmup, .main]
        )
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNil(remaining.first?.groupID)
        XCTAssertNil(remaining.first?.groupKind)
    }

    func testRouteIdentitySurvivesResequencingAndMoving() {
        let routeID = UUID()
        var run = block("Run saved route", phase: .main)
        run.routeID = routeID
        run.distanceMeters = 7_000
        run.durationSeconds = nil
        let numbered = ATHLTHWorkoutPhasePlacement.renumbered(
            run, sequence: 17
        )
        XCTAssertEqual(numbered.routeID, routeID)
        XCTAssertEqual(numbered.distanceMeters, 7_000)
        let moved = ATHLTHWorkoutPhasePlacement.relocatingSelection(
            at: 0, to: .cooldown, in: [numbered]
        )
        XCTAssertEqual(moved.first?.routeID, routeID)
    }

    func testActiveJoggingRecoveriesAreNotCountedAsAdditionalEfforts() {
        let blocks = ATHLTHRunningExercisePreset.fourByFour.blocks(in: .main)
        XCTAssertEqual(blocks.count, 8)
        let section = ATHLTHWorkoutTimelinePresentation.sections(for: blocks)
        XCTAssertEqual(section.count, 1)
        XCTAssertEqual(section[0].activityCount, 4)
        XCTAssertEqual(blocks.filter(\.isActiveRecovery).count, 4)
    }

    func testOnlyDeliberateFullLeftSwipeDeletesStep() {
        XCTAssertTrue(ATHLTHPlannedWorkoutStepRow.shouldDeleteSwipe(
            horizontal: -225, vertical: 9, rowWidth: 340
        ))
        XCTAssertFalse(ATHLTHPlannedWorkoutStepRow.shouldDeleteSwipe(
            horizontal: -70, vertical: 0, rowWidth: 340
        ))
        XCTAssertFalse(ATHLTHPlannedWorkoutStepRow.shouldDeleteSwipe(
            horizontal: 230, vertical: 0, rowWidth: 340
        ))
        XCTAssertFalse(ATHLTHPlannedWorkoutStepRow.shouldDeleteSwipe(
            horizontal: -230, vertical: 200, rowWidth: 340
        ))
    }


    func testGuidedActiveRecoveryAndWalkingKeepTheirPhasesWhenStudioOpens() {
        var activePause = block("Aktiv pause", phase: .recovery)
        activePause.activityTag = "active_recovery"
        activePause.cardioActivity = .running
        var walking = block("Gå", phase: .main)
        walking.cardioActivity = .walking

        XCTAssertTrue(activePause.isActiveRecovery)
        XCTAssertEqual(ATHLTHWorkoutPhaseDeletionPolicy.presentedPhase(
            for: activePause, visiblePhases: [.main]
        ), .recovery)
        XCTAssertEqual(ATHLTHWorkoutPhaseDeletionPolicy.orderedVisiblePhases(
            for: [activePause, walking], visiblePhases: [.main]
        ), [.recovery, .main])

        let saved = ATHLTHWorkoutPhasePlacement.renumbered(
            activePause, sequence: 1
        )
        XCTAssertTrue(saved.isActiveRecovery)
        XCTAssertEqual(saved.title, "Aktiv pause")
        XCTAssertEqual(saved.resolvedPhase, .recovery)

        let daySections = ATHLTHWorkoutTimelinePresentation.sections(
            for: [saved, walking]
        )
        XCTAssertEqual(daySections.map(\.phase), [.recovery, .main])
        XCTAssertEqual(daySections[0].blocks.first?.title, "Aktiv pause")
    }

    func testExplicitActivePauseStaysInSelectedSection() {
        var active = block("Active pause", phase: .warmup)
        active.activityTag = "active_recovery"
        active.cardioActivity = .running
        let steps = [block("Warmup", phase: .warmup), active]
        XCTAssertEqual(ATHLTHWorkoutPhaseDeletionPolicy.orderedVisiblePhases(
            for: steps, visiblePhases: [.warmup]), [.warmup])
        XCTAssertEqual(ATHLTHWorkoutPhaseDeletionPolicy.presentedPhase(
            at: 1, in: steps, visiblePhases: [.warmup]), .warmup)
    }

    func testOrdinaryRecoveryRestStillUsesMainWithoutSeparateCategory() {
        var ordinaryRest = block("Pause", phase: .recovery)
        ordinaryRest.kind = .rest
        XCTAssertFalse(ordinaryRest.isActiveRecovery)
        XCTAssertEqual(ATHLTHWorkoutPhaseDeletionPolicy.presentedPhase(
            for: ordinaryRest, visiblePhases: [.main]
        ), .main)
    }
    func testFourByFourActiveRecoveryStaysBetweenEffortsAfterPaceEditing() {
        let group = UUID()
        var source: [WorkoutTemplateBlock] = []
        for round in 1...4 {
            var work = block("Intervall \(round)", phase: .main, group: group)
            work.kind = .run
            work.groupKind = .intervals
            work.groupRounds = 1
            work.durationSeconds = 240
            work.targetPaceSecondsPerKilometer = 240 // 15 km/h
            source.append(work)
            if round < 4 {
                var rest = block("Aktiv pause \(round)", phase: .recovery, group: group)
                rest.kind = .run
                rest.groupKind = .intervals
                rest.groupRounds = 1
                rest.activityTag = "active_recovery"
                rest.cardioActivity = .running
                rest.durationSeconds = 120
                rest.targetPaceSecondsPerKilometer = 600 // 6 km/h
                rest.targetHeartRateZone = 1
                source.append(rest)
            }
        }

        let original = source
        let visible: Set<WorkoutPhaseKind> = [.main, .recovery]
        XCTAssertEqual(ATHLTHWorkoutPhaseDeletionPolicy.orderedVisiblePhases(
            for: source, visiblePhases: visible
        ), [.main], "Active interval pauses are not a separate Pause category")
        XCTAssertEqual(source.indices.map {
            ATHLTHWorkoutPhaseDeletionPolicy.presentedPhase(
                at: $0, in: source, visiblePhases: visible
            )
        }, Array(repeating: .main, count: 7))
        XCTAssertEqual(ATHLTHWorkoutTimelinePresentation.sections(
            for: source
        ).map(\.phase), [.main])
        XCTAssertEqual(ATHLTHWorkoutTimelinePresentation.sections(
            for: source
        )[0].blocks.map(\.title), [
            "Intervall 1", "Aktiv pause 1", "Intervall 2",
            "Aktiv pause 2", "Intervall 3", "Aktiv pause 3", "Intervall 4"
        ])
        XCTAssertNotNil(ATHLTHIntervalRecipeEditing.summary(for: group, in: source))
        XCTAssertEqual(source, original, "Rendering cannot change workout phases or pacing")
        let deleted = ATHLTHWorkoutPhaseDeletionPolicy.removing(
            .main, from: source, visiblePhases: visible
        )
        XCTAssertTrue(deleted.isEmpty, "Deleting Main also removes its paired recoveries")
    }

    func testStandaloneActiveRecoveryIsNotCapturedByNeighboringUnrelatedSteps() {
        var active = block("Standalone active recovery", phase: .recovery)
        active.activityTag = "active_recovery"
        active.cardioActivity = .running
        let steps = [active, block("Run", phase: .main)]
        XCTAssertEqual(ATHLTHWorkoutPhaseDeletionPolicy.presentedPhase(
            at: 0, in: steps, visiblePhases: [.main]
        ), .recovery)
        XCTAssertEqual(ATHLTHWorkoutPhaseDeletionPolicy.orderedVisiblePhases(
            for: steps, visiblePhases: [.main]
        ), [.recovery, .main])
    }

    func testFourByFourStepGuidanceDescribesCorrectRoundAndZone() {
        let group = UUID()
        var source: [WorkoutTemplateBlock] = []
        for round in 1...4 {
            var effort = block("Intervall", phase: .main, group: group)
            effort.kind = .run
            effort.groupKind = .intervals
            effort.groupRounds = 1
            effort.durationSeconds = 240
            effort.targetPaceSecondsPerKilometer = 240
            source.append(effort)
            if round < 4 {
                var rest = block("Aktiv pause", phase: .recovery, group: group)
                rest.kind = .run
                rest.activityTag = "active_recovery"
                rest.cardioActivity = .running
                rest.groupKind = .intervals
                rest.groupRounds = 1
                rest.durationSeconds = 120
                rest.targetHeartRateZone = 1
                rest.targetPaceSecondsPerKilometer = 600
                source.append(rest)
            }
        }
        let effort = ATHLTHWorkoutStepGuidance.detail(
            for: source[2], in: source
        )
        XCTAssertTrue(effort.context.contains("2"))
        XCTAssertTrue(effort.context.contains("4"))
        XCTAssertTrue(effort.instructions.contains(
            ATHLTHLocalization.isNorwegian ? "4 min" : "4 min"
        ))
        XCTAssertNotNil(effort.zone)

        let recovery = ATHLTHWorkoutStepGuidance.detail(
            for: source[3], in: source
        )
        XCTAssertTrue(recovery.context.contains("2"))
        XCTAssertTrue(recovery.context.contains("4"))
        XCTAssertTrue(recovery.instructions.contains(
            ATHLTHLocalization.isNorwegian ? "pausefart" : "recovery speed"
        ))
        XCTAssertNotNil(recovery.zone)
        XCTAssertEqual(source.map(\.durationSeconds),
                       [240, 120, 240, 120, 240, 120, 240])
    }

}
