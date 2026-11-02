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

}
