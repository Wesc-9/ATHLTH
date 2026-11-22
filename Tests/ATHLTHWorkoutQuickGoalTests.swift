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
    func testCompactOutlineCountsActualIntervalDragNotRest() {
        let group = UUID()
        var effort = part("VO2", phase: .main, order: 2, duration: 180)
        effort.groupID = group
        effort.groupKind = .intervals
        effort.groupRounds = 3
        effort.targetHeartRateZone = 5
        effort.targetHeartRatePercentMin = 90
        effort.targetHeartRatePercentMax = 100

        var recovery = part("Easy jog", kind: .rest,
                            phase: .recovery, order: 3, duration: 60)
        recovery.groupID = group
        recovery.groupKind = .intervals
        recovery.groupRounds = 3
        recovery.targetHeartRateZone = 1

        let source = [
            part("Warm-up", phase: .warmup, order: 1, duration: 600),
            effort, recovery,
            part("Cool-down", phase: .cooldown, order: 4, duration: 300)
        ]
        let rows = ATHLTHWorkoutCompactOutline.rows(for: source)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0].kind, .warmup)
        XCTAssertEqual(rows[1].kind, .work)
        XCTAssertEqual(rows[4].kind, .cooldown)
        XCTAssertEqual(rows.compactMap(\.effortIndex), [1, 2, 3])
        XCTAssertEqual(rows.filter(\.beginsMainSection).count, 1,
                       "All deløkter must stay under one visible Hoveddel")
        XCTAssertTrue(rows[1].beginsMainSection)
        XCTAssertFalse(rows[2].beginsMainSection)
        XCTAssertEqual(rows[1].effortTotal, 3)
        XCTAssertEqual(rows[1].blocks.count, 2)
        XCTAssertEqual(rows[2].blocks.count, 2)
        XCTAssertEqual(rows[3].blocks.count, 1,
                       "No mandatory recovery after the final drag")
        XCTAssertEqual(rows[1].estimatedSeconds, 240)
        XCTAssertEqual(rows[3].estimatedSeconds, 180)
        XCTAssertEqual(source[1].groupRounds, 3,
                       "Presentation never changes the original interval recipe")
    }

    func testCompactOutlineKeepsFlatIntervalAndDescriptionsOnTheirRows() {
        var source: [WorkoutTemplateBlock] = [
            part("Warm-up", phase: .warmup, order: 1, duration: 600)
        ]
        for index in 1...3 {
            source.append(part("Work \(index)", phase: .main,
                               order: index * 2, duration: 60))
            source.append(part("Rest \(index)", kind: .rest,
                               phase: .recovery, order: index * 2 + 1,
                               duration: 60))
        }
        let rows = ATHLTHWorkoutCompactOutline.rows(for: source)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.compactMap(\.effortIndex), [1, 2, 3])
        XCTAssertEqual(rows[2].blocks.map(\.title), ["Work 2", "Rest 2"])
        XCTAssertEqual(rows[2].estimatedSeconds, 120)
    }

    func testCompactHeadlineOnlyShowsPrescribedWorkZones() {
        var effort = part("Fast", phase: .main, order: 2)
        effort.targetHeartRateZone = 5
        effort.targetHeartRatePercentMin = 90
        effort.targetHeartRatePercentMax = 100
        var rest = part("Rest", kind: .rest, phase: .recovery, order: 3)
        rest.targetHeartRateZone = 1
        let blocks = [part("Warm", phase: .warmup, order: 1), effort, rest]
        XCTAssertNotNil(ATHLTHWorkoutCompactOutline.headlineZone(for: blocks))
        XCTAssertTrue(ATHLTHWorkoutCompactOutline.headlineZone(
            for: blocks
        )?.contains("Z5") == true)
        XCTAssertFalse(ATHLTHWorkoutCompactOutline.headlineZone(
            for: blocks
        )?.contains("Z1") == true)
        XCTAssertTrue(ATHLTHWorkoutCompactOutline.headlineHeartRatePercent(
            for: blocks
        )?.contains("90–100") == true)
        XCTAssertNil(ATHLTHWorkoutCompactOutline.headlineZone(for: [
            part("Unspecified", phase: .main, order: 1)
        ]))
        XCTAssertNil(ATHLTHWorkoutCompactOutline.headlineHeartRatePercent(
            for: [part("Unspecified", phase: .main, order: 1)]
        ))
    }

}
