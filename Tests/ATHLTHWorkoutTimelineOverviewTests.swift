import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutTimelineOverviewTests: XCTestCase {
    func testRepeatedLegacyBlocksHaveDistinctTimelineSectionIdentities() {
        let effort = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Effort",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 60,
            targetWeightKilograms: nil, loadNote: nil, notes: nil,
            phase: .main)
        let rest = WorkoutTemplateBlock(
            sequence: 1, kind: .rest, title: "Rest",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 30,
            targetWeightKilograms: nil, loadNote: nil, notes: nil,
            phase: .recovery)
        let sections = ATHLTHWorkoutTimelineOverview.sections(for: [effort, rest, effort, rest])
        XCTAssertEqual(sections.count, 4)
        XCTAssertEqual(Set(sections.map(\.id)).count, 4)
        XCTAssertEqual(sections.flatMap(\.blocks), [effort, rest, effort, rest])
    }

    func testPreviewPreservesInlineRecoveryAndRepeatedPhases() {
        func block(_ title: String, phase: WorkoutPhaseKind) -> WorkoutTemplateBlock {
            WorkoutTemplateBlock(
                sequence: 1, kind: .run, title: title,
                exerciseSlug: nil, distanceMeters: nil,
                repetitions: nil, durationSeconds: 60,
                targetWeightKilograms: nil, loadNote: nil, notes: nil,
                phase: phase)
        }
        let blocks = [block("Warmup", phase: .warmup),
                      block("Effort 1", phase: .main),
                      block("Recovery", phase: .recovery),
                      block("Effort 2", phase: .main),
                      block("Effort 3", phase: .main),
                      block("Cooldown", phase: .cooldown)]
        let sections = ATHLTHWorkoutTimelineOverview.sections(for: blocks)
        XCTAssertEqual(sections.map(\.phase), [.warmup, .main, .recovery, .main, .cooldown])
        XCTAssertEqual(sections.flatMap(\.blocks).map(\.id), blocks.map(\.id))
        XCTAssertEqual(sections[3].blocks.map(\.title), ["Effort 2", "Effort 3"])
    }
}
