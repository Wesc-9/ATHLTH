import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutCaptureAdmissionTests: XCTestCase {
    private func block(_ kind: WorkoutTemplateBlockKind,
                       sequence: Int = 1) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: sequence, kind: kind, title: "Step",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 300, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )
    }

    private func session(_ kind: WorkoutKind,
                         blocks: [WorkoutTemplateBlock] = [],
                         category: String? = nil) -> PlannedSession {
        var workout = PlannedSession(
            id: UUID(), title: "Session", kind: kind,
            scheduledStart: nil, durationMinutes: 30,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        workout.workoutBlocks = blocks.isEmpty ? nil : blocks
        workout.workoutCategory = category
        return workout
    }

    func testSupportedStrengthAndRunStrengthHybridRemainAdmissible() {
        XCTAssertNoThrow(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.strength, blocks: [block(.exercise)])
            ))
        XCTAssertNoThrow(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.custom, blocks: [
                    block(.run), block(.exercise, sequence: 2)
                ])
            ))
        XCTAssertNoThrow(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.strength, blocks: [
                    block(.exercise), block(.rest, sequence: 2),
                    block(.note, sequence: 3)
                ])
            ))
    }

    func testCyclingStrengthCannotBecomeFakeStrengthRecording() {
        var cycle = block(.note)
        cycle.activityTag = "cycling"
        XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.strength, blocks: [
                    cycle, block(.exercise, sequence: 2)
                ])
            ))
        XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.custom, category: "cycling")
            ))
    }

    func testYogaAndMeditationCannotBecomeStrengthRecording() {
        var yoga = block(.note)
        yoga.wellnessKind = .yoga
        var meditation = block(.note)
        meditation.wellnessKind = .meditation
        for wellness in [yoga, meditation] {
            XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
                .requireSupportedStrengthCapture(
                    for: session(.strength, blocks: [
                        block(.exercise), wellness
                    ])
                ))
        }
    }

    func testOtherActivityWithoutStrengthIsNotAccepted() {
        XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.running, blocks: [block(.run)])
            ))
        XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.custom, category: "hybrid")
            ))
        XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.mobility)
            ))
    }

    func testFreeStrengthWithoutStructuredBlocksStillSupported() {
        XCTAssertNoThrow(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(for: session(.strength)))
    }
}
