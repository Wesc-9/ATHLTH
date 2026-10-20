import Foundation
import XCTest
@testable import ATHLTH

/// The planner's previews must count the actual selected interval repetitions,
/// while keeping distance optional and excluding stationary recovery distance.
final class ATHLTHRunningPlanningEstimateTests: XCTestCase {
    private func intensity(secondsPerKm: Double) -> RunningIntensityTarget {
        RunningIntensityTarget(
            kind: .pace,
            paceMinSecondsPerKilometer: secondsPerKm,
            paceMaxSecondsPerKilometer: secondsPerKm,
            heartRateZone: nil,
            rpe: nil
        )
    }

    private func makeWorkout(blocks: [RunningWorkoutBlock]) -> RunningWorkoutTemplate {
        RunningWorkoutTemplate(
            id: UUID(), title: "4 × 4 intervaller",
            type: .intervals, summary: "", blocks: blocks,
            routeID: nil, isBuiltIn: false,
            createdAt: Date(), updatedAt: Date()
        )
    }

    func testFourByFourEstimatesAllPhasesAndThreeStationaryRecoveries() {
        let workout = makeWorkout(blocks: [
            RunningWorkoutBlock(
                kind: .warmup, title: "Oppvarming",
                work: .time(600)
            ),
            RunningWorkoutBlock(
                kind: .work, title: "4 × 4", repetitions: 4,
                work: .time(240, intensity: intensity(secondsPerKm: 300)),
                recovery: .time(120)
            ),
            RunningWorkoutBlock(
                kind: .cooldown, title: "Nedjogg",
                work: .time(600)
            )
        ])
        let estimate = ATHLTHRunningPlanningEstimate.totals(
            for: [workout], defaultPaceSecondsPerKilometer: 360
        )
        XCTAssertEqual(estimate.durationSeconds ?? 0, 42 * 60, accuracy: 0.01)
        // Warm-up (1.667 km) + efforts (3.2 km) + stationary
        // rests (0 km) + cool-down (1.667 km).
        XCTAssertEqual(estimate.distanceMeters ?? 0, 6_533.333, accuracy: 0.5)
    }

    func testTargetPaceCanAdjustEstimateWithoutChangingFixedIntervalDuration() {
        let workout = makeWorkout(blocks: [
            RunningWorkoutBlock(kind: .work, title: "Drag",
                                repetitions: 4, work: .time(240)),
        ])
        let slower = ATHLTHRunningPlanningEstimate.totals(
            for: [workout], defaultPaceSecondsPerKilometer: 360
        )
        let faster = ATHLTHRunningPlanningEstimate.totals(
            for: [workout], defaultPaceSecondsPerKilometer: 300
        )
        XCTAssertEqual(slower.durationSeconds ?? 0, 960, accuracy: 0.01)
        XCTAssertEqual(faster.durationSeconds ?? 0, 960, accuracy: 0.01)
        XCTAssertEqual(slower.distanceMeters ?? 0, 2_666.667, accuracy: 0.5)
        XCTAssertEqual(faster.distanceMeters ?? 0, 3_200, accuracy: 0.5)
    }

    func testExplicitRecoverySpeedCountsAsWalkingOrJoggingDistance() {
        let workout = makeWorkout(blocks: [
            RunningWorkoutBlock(
                kind: .work, title: "4 × 4", repetitions: 4,
                work: .time(240, intensity: intensity(secondsPerKm: 300)),
                recovery: .time(120, intensity: intensity(secondsPerKm: 600))
            )
        ])
        let estimate = ATHLTHRunningPlanningEstimate.totals(for: [workout])
        XCTAssertEqual(estimate.durationSeconds ?? 0, 1_320, accuracy: 0.01)
        XCTAssertEqual(estimate.distanceMeters ?? 0, 3_800, accuracy: 0.01)
    }

    func testOpenEndedStepsCannotInventTargetDistanceOrTime() {
        let workout = makeWorkout(blocks: [
            RunningWorkoutBlock(kind: .steady, title: "Fri løping",
                                work: .open)
        ])
        let estimate = ATHLTHRunningPlanningEstimate.totals(for: [workout])
        XCTAssertNil(estimate.distanceMeters)
        XCTAssertNil(estimate.durationSeconds)
    }

    func testTreadmillKilometersPerHourConvertsToSecondsPerKilometer() {
        // Standard treadmill display: 12 km/t => 5:00 min/km.
        let speedKilometersPerHour = 12.0
        let targetPaceSecondsPerKm = 3_600 / speedKilometersPerHour
        XCTAssertEqual(targetPaceSecondsPerKm, 300)
        let workout = makeWorkout(blocks: [
            RunningWorkoutBlock(kind: .steady, title: "Mølle",
                                work: .time(600))
        ])
        let estimate = ATHLTHRunningPlanningEstimate.totals(
            for: [workout],
            defaultPaceSecondsPerKilometer: targetPaceSecondsPerKm
        )
        XCTAssertEqual(estimate.distanceMeters ?? 0, 2_000, accuracy: 0.01)
    }
}
