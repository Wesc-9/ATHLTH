import XCTest
@testable import ATHLTH

final class ATHLTHLiveRunningWarmupRecipeTests: XCTestCase {
    private func session() -> PlannedSession {
        let template = RunningWorkoutLibraryStore.builtInTemplates[0]
        return PlannedSession(
            id: UUID(),
            title: template.title,
            kind: .running,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: template.summary,
            runningWorkout: template
        )
    }

    func testSelectedIntervalsBeginWithTenMinuteWarmupWithoutChangingLibrarySource() {
        let original = session()
        let originalBlocks = original.runningWorkout?.blocks
        let selected = ATHLTHLiveRunningWarmupRecipe.make(session: original)
        let first = selected.runningWorkout?.blocks.first

        XCTAssertEqual(first?.kind, .warmup)
        XCTAssertEqual(first?.work.durationSeconds, 600)
        XCTAssertEqual(first?.repetitions, 1)
        XCTAssertEqual(selected.runningWorkout?.autoStartMainAfterWarmup, true)
        XCTAssertEqual(original.runningWorkout?.blocks, originalBlocks)
    }

    func testWarmupAllowsPaceZoneAndInclineTargets() {
        let selected = ATHLTHLiveRunningWarmupRecipe.make(
            session: session(),
            minutes: 14,
            paceSecondsPerKilometer: 330,
            heartRateZone: 2,
            inclinePercent: 2.5
        )
        let first = selected.runningWorkout?.blocks.first
        XCTAssertEqual(first?.work.durationSeconds, 840)
        XCTAssertEqual(first?.work.intensity.paceMinSecondsPerKilometer, 330)
        XCTAssertEqual(first?.work.intensity.heartRateZone, 2)
        XCTAssertEqual(first?.work.treadmillInclinePercent, 2.5)
    }

    func testStartingIntervalsNowSkipsWarmupWithoutSkippingFirstEffort() {
        let selected = ATHLTHLiveRunningWarmupRecipe.make(
            session: session(), skipWarmup: true
        )
        XCTAssertFalse(selected.runningWorkout?.blocks.contains {
            $0.kind == .warmup
        } ?? true)
        XCTAssertEqual(selected.runningWorkout?.blocks.first?.kind, .work)
    }
}
