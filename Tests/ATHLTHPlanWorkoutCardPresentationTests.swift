import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlanWorkoutCardPresentationTests: XCTestCase {
    private func step(
        _ name: String, kind: WorkoutTemplateBlockKind = .run,
        phase: WorkoutPhaseKind = .main, seconds: Double = 240
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: kind, title: name,
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: seconds, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: phase
        )
    }

    func testFourByFourPausesAppearImmediatelyAfterEfforts() {
        let workout: [WorkoutTemplateBlock] = [
            step("Oppvarming", phase: .warmup, seconds: 600),
            step("Intervall 1"),
            step("Pause", kind: .rest, phase: .recovery, seconds: 120),
            step("Intervall 2"),
            step("Pause", kind: .rest, phase: .recovery, seconds: 120),
            step("Intervall 3"),
            step("Pause", kind: .rest, phase: .recovery, seconds: 120),
            step("Intervall 4"),
            step("Nedjogging", phase: .cooldown, seconds: 600)
        ]
        let sections = ATHLTHPlanWorkoutCardPresentation.sections(for: workout)
        XCTAssertEqual(sections.map(\.phase), [.warmup, .main, .cooldown])
        XCTAssertEqual(sections.map(\.activityCount), [1, 4, 1])
        XCTAssertEqual(sections[1].entries.map { $0.block.title },
            ["Intervall 1", "Pause", "Intervall 2", "Pause",
             "Intervall 3", "Pause", "Intervall 4"])
        XCTAssertEqual(sections.flatMap(\.entries).count, 9)
    }

    func testCompactFourRoundIntervalShowsThreeRestPeriods() {
        let group = UUID()
        var effort = step("Intervall")
        effort.groupID = group
        effort.groupKind = .intervals
        effort.groupRounds = 4
        var pause = step("Pause", kind: .rest, phase: .recovery, seconds: 120)
        pause.groupID = group
        pause.groupKind = .intervals
        pause.groupRounds = 4

        let entries = ATHLTHPlanWorkoutCardPresentation.entries(from: [effort, pause])
        XCTAssertEqual(entries.count, 7)
        XCTAssertEqual(entries.filter { $0.block.kind == .rest }.count, 3)
        XCTAssertTrue(entries.allSatisfy { $0.sourceIndex == 0 })
        XCTAssertTrue(entries.allSatisfy { $0.groupSteps?.count == 7 })
    }

    func testPaceAndInclineAreOptionalAndPreserved() {
        var item = step("Intervall")
        let empty = ATHLTHPlanWorkoutCardPresentation.facts(for: item)
        XCTAssertFalse(empty.contains { $0.contains("4:30/km") || $0.contains("%") })

        item.targetPaceSecondsPerKilometer = 270
        item.treadmillInclinePercent = 3.0
        let facts = ATHLTHPlanWorkoutCardPresentation.facts(for: item)
        XCTAssertTrue(facts.contains { $0.contains("4:30/km") })
        XCTAssertTrue(facts.contains { $0.contains("3.0 %") })

        item.treadmillInclinePercent = nil
        XCTAssertFalse(ATHLTHPlanWorkoutCardPresentation.facts(for: item)
            .contains { $0.contains("3.0 %") })
    }

    func testStrengthExerciseExpandsAllSetsWithNoFinalPause() {
        var squat = step("Knebøy", kind: .exercise, seconds: 60)
        squat.setCount = 3
        squat.restBetweenSetsSeconds = 90
        let entries = ATHLTHPlanWorkoutCardPresentation.entries(from: [squat])
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries.filter { $0.block.kind == .rest }.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.sourceIndex == 0 })
    }
}
