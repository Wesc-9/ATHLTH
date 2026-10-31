import XCTest
@testable import ATHLTH

final class ATHLTHQuickRunTimelineAdapterTests: XCTestCase {
    private func block(
        _ name: String, kind: WorkoutTemplateBlockKind = .run,
        phase: WorkoutPhaseKind, seconds: Double
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: kind, title: name, exerciseSlug: nil,
            distanceMeters: nil, repetitions: nil, durationSeconds: seconds,
            targetWeightKilograms: nil, loadNote: nil, notes: nil, phase: phase
        )
    }

    private func workout(_ blocks: [WorkoutTemplateBlock]) -> PlannedSession {
        var session = PlannedSession(
            id: UUID(), title: "Intervals", kind: .running,
            scheduledStart: nil, durationMinutes: 30,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        session.workoutBlocks = blocks
        return session
    }

    func testSharedTimelinePreservesRunningPhases() {
        let warmup = block("Warm up", phase: .warmup, seconds: 600)
        var work = block("Work", phase: .main, seconds: 240)
        work.targetHeartRateZone = 4
        work.targetPaceSecondsPerKilometer = 270
        let rest = block("Rest", kind: .rest, phase: .recovery, seconds: 120)
        let source = workout([warmup, work, rest])
        let result = ATHLTHQuickRunTimelineAdapter.transfer(
            from: source, title: source.title,
            routeAlerts: .standard, autoPauseEnabled: true
        )
        XCTAssertEqual(result?.steps.map(\.phase), ["warmup", "work", "recovery"])
        XCTAssertEqual(result?.steps.map(\.durationSeconds), [600, 240, 120])
        XCTAssertEqual(result?.steps[1].targetHeartRateZone, 4)
        XCTAssertEqual(result?.steps[1].targetPaceMinSecondsPerKilometer, 270)
        XCTAssertEqual(result?.sourceWorkoutID, source.id)
    }

    func testIntervalRoundsUseSameExpansionAsPlan() {
        let id = UUID()
        var work = block("Fast", phase: .main, seconds: 240)
        work.groupID = id
        work.groupKind = .intervals
        work.groupRounds = 4
        var recovery = block("Jog", kind: .rest, phase: .recovery, seconds: 120)
        recovery.groupID = id
        recovery.groupKind = .intervals
        recovery.groupRounds = 4
        let transfer = ATHLTHQuickRunTimelineAdapter.transfer(
            from: workout([work, recovery]), title: "4 × 4",
            routeAlerts: .standard, autoPauseEnabled: false
        )
        XCTAssertEqual(transfer?.steps.filter { $0.phase == "work" }.count, 4)
        XCTAssertEqual(transfer?.steps.filter { $0.phase == "recovery" }.count, 3)
    }

    func testStrengthOrMixedWorkoutIsRejected() {
        let run = block("Run", phase: .main, seconds: 600)
        let strength = block("Strength", kind: .exercise, phase: .main, seconds: 60)
        XCTAssertNotNil(ATHLTHQuickRunTimelineAdapter.validationError(
            for: workout([run, strength])
        ))
    }

    func testTreadmillSelectionUsesPlanMetadata() {
        var run = block("Treadmill", phase: .main, seconds: 600)
        run.isIndoor = true
        run.treadmillInclinePercent = 2
        XCTAssertEqual(
            ATHLTHQuickRunTimelineAdapter.environment(for: workout([run])),
            .treadmill
        )
    }
}
