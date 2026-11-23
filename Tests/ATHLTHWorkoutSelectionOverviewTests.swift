import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutSelectionOverviewTests: XCTestCase {
    private func strength(
        _ title: String = "Back Extension",
        slug: String = "back-extension",
        sets: Int = 3,
        rest: TimeInterval? = 90
    ) -> WorkoutTemplateBlock {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: title,
            exerciseSlug: slug, distanceMeters: nil,
            repetitions: 8, durationSeconds: nil,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
        block.setCount = sets
        block.restBetweenSetsSeconds = rest
        return block
    }

    private func pause(
        _ title: String, seconds: TimeInterval? = 60
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 2, kind: .rest, title: title,
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: seconds,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .recovery
        )
    }

    func testThreeSetsHaveTwoBetweenSetPausesAndOneExercise() {
        let workout = [strength()]
        let metrics = ATHLTHWorkoutSelectionOverview.metrics(for: workout)
        XCTAssertEqual(metrics.exerciseCount, 1)
        XCTAssertEqual(metrics.setCount, 3)
        XCTAssertEqual(metrics.pauseCount, 2)
        XCTAssertEqual(metrics.executedStepCount, 5)
        XCTAssertEqual(metrics.restSeconds, 180)
        // Existing estimation: 8 reps × 4s + 15s setup per set.
        XCTAssertEqual(metrics.activeSeconds ?? -1, 141, accuracy: 0.01)
        XCTAssertEqual(metrics.totalSeconds ?? -1, 321, accuracy: 0.01)

        let rows = ATHLTHWorkoutSelectionOverview.rows(for: workout)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].sets, 3)
        XCTAssertEqual(rows[0].betweenSetPauses, 2)
        XCTAssertEqual(rows[0].betweenSetRestSeconds, 180)
        XCTAssertEqual(rows[0].title, "Back Extension")
    }

    func testSelectionSectionsExposeActualExerciseNamesAndSetTargets() {
        var warmup = strength("Band pull apart", sets: 2, rest: nil)
        warmup.phase = .warmup
        let main = strength("Back Extension", sets: 3)
        var cooldown = strength("Stretch", sets: 1, rest: nil)
        cooldown.phase = .cooldown
        cooldown.repetitions = nil
        cooldown.durationSeconds = 45
        let recipe = [warmup, main, cooldown]
        let sections = ATHLTHWorkoutSelectionOverview.sections(for: recipe)
        XCTAssertEqual(sections.map(\.phase), [.warmup, .main, .cooldown])
        XCTAssertEqual(sections.flatMap(\.rows).map(\.title),
                       ["Band pull apart", "Back Extension", "Stretch"])
        XCTAssertEqual(sections[0].rows[0].prescription, "2 × 8 reps")
        XCTAssertEqual(sections[1].rows[0].prescription, "3 × 8 reps")
        XCTAssertEqual(sections[2].rows[0].prescription, "1 × 45 s")
        XCTAssertEqual(recipe[1].setCount, 3)
    }

    func testSelectionPreservesDifferentRepTargetsAndTransitionPauses() {
        var first = strength("Squat", sets: 1, rest: nil)
        first.repetitions = 8
        first.title = "Squat · 1/2"
        var second = first
        second.title = "Squat · 2/2"
        second.repetitions = 6
        let recipe = [first, second, pause("Mellom øvelser", seconds: 90),
                      strength("Press", slug: "press", sets: 1, rest: nil)]
        let sections = ATHLTHWorkoutSelectionOverview.sections(for: recipe)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].rows.map(\.title), ["Squat", "Pause", "Press"])
        XCTAssertTrue(sections[0].rows[0].prescription.contains("8 / 6 reps"))
        XCTAssertTrue(sections[0].rows[1].isPause)
    }

    func testNoImplicitPauseIsInsertedBetweenDifferentExercises() {
        let workout = [
            strength("Back Extension", slug: "back", sets: 1, rest: nil),
            strength("Pulldown", slug: "pulldown", sets: 1, rest: nil)
        ]
        let metrics = ATHLTHWorkoutSelectionOverview.metrics(for: workout)
        XCTAssertEqual(metrics.exerciseCount, 2)
        XCTAssertEqual(metrics.setCount, 2)
        XCTAssertEqual(metrics.pauseCount, 0)
        XCTAssertEqual(ATHLTHWorkoutSelectionOverview.rows(for: workout).count, 2)
    }

    func testExplicitTransitionPauseIsPreservedAndNotGroupedWithSets() {
        let workout = [
            strength(sets: 2),
            pause("Mellom øvelser", seconds: 120),
            strength("Lat Pulldown", slug: "pulldown", sets: 2)
        ]
        let metrics = ATHLTHWorkoutSelectionOverview.metrics(for: workout)
        XCTAssertEqual(metrics.exerciseCount, 2)
        XCTAssertEqual(metrics.setCount, 4)
        XCTAssertEqual(metrics.pauseCount, 3)
        XCTAssertEqual(metrics.restSeconds, 300)
        XCTAssertTrue(metrics.hasBetweenExerciseRest)
        let rows = ATHLTHWorkoutSelectionOverview.rows(for: workout)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].sets, 2)
        XCTAssertEqual(rows[1].title, "Pause")
        XCTAssertTrue(rows[1].subtitle.contains("Mellom øvelser"))
        XCTAssertEqual(rows[2].sets, 2)
    }

    func testPauseIsMainTitleAndBetweenSetIsSubtitle() {
        let block = pause("Mellom sett", seconds: 90)
        let row = ATHLTHWorkoutSelectionOverview.Row(id: 0, steps: [block])
        XCTAssertEqual(row.title, "Pause")
        XCTAssertTrue(row.subtitle.contains(
            ATHLTHLocalization.choose(
                english: "Between sets", norwegian: "Mellom sett"
            )
        ))
        XCTAssertTrue(row.subtitle.contains("1:30"))
    }

    func testUnknownRestLeavesEstimatedRestAndActiveTimeUnknown() {
        let workout = [strength(sets: 1), pause("Pause", seconds: nil)]
        let metrics = ATHLTHWorkoutSelectionOverview.metrics(for: workout)
        XCTAssertEqual(metrics.pauseCount, 1)
        XCTAssertNil(metrics.restSeconds)
        XCTAssertNil(metrics.activeSeconds)
        XCTAssertNil(metrics.totalSeconds)
    }

    func testWorkoutGroupRoundsAreNeverCollapsedIntoStandaloneSets() {
        let groupID = UUID()
        var member = strength(sets: 1)
        member.groupID = groupID
        member.groupKind = .superset
        member.groupRounds = 3
        var other = strength("Lat Pulldown", slug: "pulldown", sets: 1)
        other.groupID = groupID
        other.groupKind = .superset
        other.groupRounds = 3
        let executed = [member, other].expandedForExecution()
        let rows = ATHLTHWorkoutSelectionOverview.rows(for: [member, other])
        XCTAssertEqual(rows.count, executed.count)
        XCTAssertTrue(rows.allSatisfy { $0.sets == 1 })
    }

    func testActiveRecoveryCountsAsPauseButNotPassiveRest() {
        let active = ATHLTHActiveRecovery.convert(
            pause("Pause", seconds: 60), active: true
        )
        let metrics = ATHLTHWorkoutSelectionOverview.metrics(for: [active])
        XCTAssertEqual(metrics.pauseCount, 1)
        XCTAssertEqual(metrics.restSeconds, 0)
        XCTAssertEqual(metrics.activeSeconds, 60)
        XCTAssertEqual(metrics.totalSeconds, 60)
    }

    func testMusclesAndEquipmentComeFromRealEmbeddedExerciseMetadata() {
        var item = strength(sets: 2)
        item.exerciseSnapshot = ExerciseSnapshot(
            name: "Back Extension", instructions: [],
            primaryMuscles: ["Back"], equipment: ["Machine"], imageURL: nil
        )
        let metrics = ATHLTHWorkoutSelectionOverview.metrics(for: [item])
        XCTAssertEqual(metrics.primaryMuscles, ["Back"])
        XCTAssertEqual(metrics.equipment, ["Machine"])
    }
}
