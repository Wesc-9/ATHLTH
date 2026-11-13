import Foundation
import XCTest
@testable import ATHLTH

/// Quick targets are an optional projection on the shared executable recipe.
/// Choosing a goal must never rewrite warm-up, recoveries, original templates
/// or personal metrics outside the work portion.
final class ATHLTHWorkoutQuickGoalTests: XCTestCase {
    private func part(
        _ title: String,
        kind: WorkoutTemplateBlockKind = .run,
        phase: WorkoutPhaseKind,
        order: Int,
        duration: Double = 120
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: order, kind: kind, title: title,
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: duration, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: phase
        )
    }

    func testTargetPaceOnlyChangesMainRunningWork() {
        let source = [
            part("Warm-up", phase: .warmup, order: 1, duration: 600),
            part("Effort", phase: .main, order: 2, duration: 180),
            part("Recovery", kind: .rest, phase: .recovery, order: 3),
            part("Cool-down", phase: .cooldown, order: 4, duration: 600)
        ]
        let result = ATHLTHWorkoutQuickGoalApplier.apply(
            .pace(secondsPerKilometer: 285), to: source
        )
        XCTAssertEqual(result[1].targetPaceSecondsPerKilometer, 285)
        XCTAssertNil(result[0].targetPaceSecondsPerKilometer)
        XCTAssertNil(result[2].targetPaceSecondsPerKilometer)
        XCTAssertNil(result[3].targetPaceSecondsPerKilometer)
        XCTAssertEqual(result.map(\.durationSeconds), source.map(\.durationSeconds))
        XCTAssertEqual(result.map(\.sequence), source.map(\.sequence))
        XCTAssertEqual(source[1].targetPaceSecondsPerKilometer, nil)
    }

    func testHeartRateZoneIsOptionalAndDoesNotInventPace() {
        let original = [part("Test", phase: .main, order: 1)]
        let zoned = ATHLTHWorkoutQuickGoalApplier.apply(
            .heartRateZone(4), to: original
        )
        XCTAssertEqual(zoned[0].targetHeartRateZone, 4)
        XCTAssertNil(zoned[0].targetPaceSecondsPerKilometer)
        XCTAssertEqual(
            ATHLTHWorkoutQuickGoalApplier.apply(.none, to: original),
            original
        )
    }

    func testRunningTemplatePaceChangesEffortNotWarmupOrRest() {
        let source = RunningWorkoutTemplate(
            id: UUID(), title: "4 × 4", type: .intervals,
            summary: "Running", blocks: [
                RunningWorkoutBlock(kind: .warmup, title: "Warm-up",
                                    work: .time(600)),
                RunningWorkoutBlock(kind: .work, title: "Effort",
                                    repetitions: 4, work: .time(240),
                                    recovery: .time(120)),
                RunningWorkoutBlock(kind: .cooldown, title: "Cool-down",
                                    work: .time(600))
            ],
            routeID: nil, isBuiltIn: false,
            createdAt: Date(), updatedAt: Date()
        )
        let target = ATHLTHWorkoutQuickGoalApplier.apply(
            .pace(secondsPerKilometer: 260), to: source
        )
        XCTAssertEqual(target.blocks[1].work.intensity.kind, .pace)
        XCTAssertEqual(target.blocks[1].work.intensity.paceMinSecondsPerKilometer, 260)
        XCTAssertEqual(target.blocks[1].work.intensity.paceMaxSecondsPerKilometer, 260)
        XCTAssertNil(target.blocks[0].work.intensity.paceMinSecondsPerKilometer)
        XCTAssertNil(target.blocks[2].work.intensity.paceMinSecondsPerKilometer)
        XCTAssertNil(target.blocks[1].recovery?.intensity.paceMinSecondsPerKilometer)
        XCTAssertNil(source.blocks[1].work.intensity.paceMinSecondsPerKilometer)
        XCTAssertEqual(target.blocks[1].repetitions, 4)
        XCTAssertEqual(target.blocks[1].work.durationSeconds, 240)
    }

    func testQuickTargetAlsoWorksForSteadyRuns() {
        let source = RunningWorkoutTemplate(
            id: UUID(), title: "Easy 30", type: .easy,
            summary: "Steady running", blocks: [
                RunningWorkoutBlock(kind: .steady, title: "Easy running",
                                    work: .time(1800))
            ],
            routeID: nil, isBuiltIn: false,
            createdAt: Date(), updatedAt: Date()
        )
        let result = ATHLTHWorkoutQuickGoalApplier.apply(
            .pace(secondsPerKilometer: 360), to: source
        )
        XCTAssertEqual(result.blocks[0].work.intensity.kind, .pace)
        XCTAssertEqual(result.blocks[0].work.intensity.paceMinSecondsPerKilometer, 360)
        XCTAssertEqual(result.blocks[0].work.durationSeconds, 1800)
        XCTAssertNil(source.blocks[0].work.intensity.paceMinSecondsPerKilometer)
    }

    func testNoTargetKeepsRunningPrescriptionUnchanged() {
        let source = RunningWorkoutTemplate(
            id: UUID(), title: "Recovery", type: .easy,
            summary: "Easy run",
            blocks: [
                RunningWorkoutBlock(kind: .steady, title: "Easy",
                                    work: .time(1800))
            ],
            routeID: nil, isBuiltIn: false,
            createdAt: Date(), updatedAt: Date()
        )
        let unchanged = ATHLTHWorkoutQuickGoalApplier.apply(.none, to: source)
        XCTAssertEqual(
            unchanged.blocks[0].work.durationSeconds,
            source.blocks[0].work.durationSeconds
        )
        XCTAssertNil(unchanged.blocks[0].work.intensity.paceMinSecondsPerKilometer)
    }
}
