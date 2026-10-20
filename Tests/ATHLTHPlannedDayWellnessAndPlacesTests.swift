import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlannedDayWellnessAndPlacesTests: XCTestCase {
    private func timedWellness(
        _ type: WorkoutWellnessKind = .meditation,
        seconds: TimeInterval = 300
    ) -> WorkoutTemplateBlock {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .note, title: type.title,
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: seconds, targetWeightKilograms: nil,
            loadNote: nil, notes: nil,
            phase: type == .meditation ? .recovery : .main
        )
        block.wellnessKind = type
        return block
    }

    func testMeditationWithoutStrengthCanBeScheduledAndTimed() throws {
        let meditation = timedWellness()
        XCTAssertEqual(ATHLTHWorkoutDurationEstimator.minutes(for: [meditation]), 5)
        XCTAssertEqual([meditation].expandedForExecution().first?.wellnessKind,
                       .meditation)

        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Fem minutter ro", kind: .recovery,
            durationMinutes: 5, routeID: nil, blocks: [meditation]
        )
        XCTAssertTrue(blueprint.isValid)
        let scheduled = blueprint.applying(to: nil)
        XCTAssertEqual(scheduled.kind, .recovery)
        XCTAssertEqual(scheduled.workoutCategory, "recovery")
    }

    func testStretchingCanBeAStandalonePlannedWorkout() {
        let stretching = timedWellness(.stretching, seconds: 600)
        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Uttøying", kind: .mobility,
            durationMinutes: 10, routeID: nil, blocks: [stretching]
        )
        XCTAssertTrue(blueprint.isValid)
        XCTAssertEqual(ATHLTHWorkoutDurationEstimator.minutes(for: [stretching]), 10)
    }

    func testPlaceStaysOnOneDayAndDoesNotBecomeMeetingPoint() {
        let place = ATHLTHTrainingPlace(kind: .hotel,
             name: "Hotel gym", address: "Testveien 20")
        var edit = ATHLTHPlanWeekDayEdit()
        edit.trainingPlace = place
        let sample = PlannedSession(
            id: UUID(), title: "4x4", kind: .running,
            scheduledStart: nil, durationMinutes: 30,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: nil
        )
        let chosen = edit.scheduledSessions(from: [sample])
        XCTAssertEqual(chosen.first?.plannedTrainingPlace, place)
        XCTAssertNil(chosen.first?.meetingPoint)
        XCTAssertNil(ATHLTHPlanWeekDayEdit().scheduledSessions(from: [sample])
            .first?.plannedTrainingPlace)
        edit.isRestDay = true
        XCTAssertTrue(edit.scheduledSessions(from: [sample]).isEmpty)
    }

    func testWarmupHasIndependentTimePaceAndHeartRateZone() {
        var warmup = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Oppvarming – rolig jogg",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 600, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .warmup,
            targetPaceSecondsPerKilometer: 360, targetHeartRateZone: 2
        )
        warmup.cardioActivity = .running
        var effort = warmup
        effort.title = "4x4 hoveddel"
        effort.phase = .main
        effort.durationSeconds = 240
        effort.targetPaceSecondsPerKilometer = 270
        effort.targetHeartRateZone = 4
        let blocks = [warmup, effort].expandedForExecution()
        XCTAssertEqual(blocks.first?.resolvedPhase, .warmup)
        XCTAssertEqual(blocks.first?.targetPaceSecondsPerKilometer, 360)
        XCTAssertEqual(blocks.first?.targetHeartRateZone, 2)
        XCTAssertEqual(blocks.last?.resolvedPhase, .main)
        XCTAssertEqual(blocks.last?.targetHeartRateZone, 4)
    }
}
