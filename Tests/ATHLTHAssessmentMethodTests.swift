import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAssessmentMethodTests: XCTestCase {
    private func step(
        phase: WorkoutPhaseKind, kind: WorkoutTemplateBlockKind = .run
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: kind, title: "Test",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 180, targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: phase
        )
    }

    func testMainOnlyMeasurementDoesNotLeakIntoWarmupOrCooldown() throws {
        var main = step(phase: .main)
        main.assessmentMethod = .threeMinuteAllOut
        XCTAssertEqual(
            ATHLTHAssessmentMethod.normalized(main.assessmentMethod, for: main),
            .threeMinuteAllOut
        )
        for phase in [WorkoutPhaseKind.warmup, .cooldown, .recovery] {
            var step = main
            step.phase = phase
            XCTAssertNil(
                ATHLTHAssessmentMethod.normalized(step.assessmentMethod, for: step)
            )
        }
        let expanded = [main].expandedForExecution()
        XCTAssertEqual(expanded.count, 1)
        XCTAssertEqual(expanded.first?.assessmentMethod, .threeMinuteAllOut)
    }

    func testStrengthMethodNotAvailableOnRunningAndViceVersa() {
        let running = step(phase: .main)
        let strength = step(phase: .main, kind: .exercise)
        XCTAssertTrue(ATHLTHAssessmentMethod.available(for: running)
            .contains(.cooperTwelveMinute))
        XCTAssertFalse(ATHLTHAssessmentMethod.available(for: running)
            .contains(.estimatedOneRepMax))
        XCTAssertEqual(
            ATHLTHAssessmentMethod.available(for: strength),
            [.estimatedOneRepMax]
        )
        XCTAssertNil(ATHLTHAssessmentMethod.normalized(
            .estimatedOneRepMax, for: running
        ))
        XCTAssertNil(ATHLTHAssessmentMethod.normalized(
            .threeMinuteAllOut, for: strength
        ))
        var walking = running
        walking.cardioActivity = .walking
        XCTAssertTrue(ATHLTHAssessmentMethod.available(for: walking).isEmpty)
        var resting = running
        resting.kind = .rest
        XCTAssertTrue(ATHLTHAssessmentMethod.available(for: resting).isEmpty)
    }

    func testMeasurementSelectionSurvivesSavedRecipeAndPhaseRenumbering() throws {
        var main = step(phase: .main)
        main.assessmentMethod = .cooperTwelveMinute
        let encoded = try JSONEncoder().encode(main)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self)
            .contains("assessment_method"))
        let decoded = try JSONDecoder().decode(WorkoutTemplateBlock.self, from: encoded)
        XCTAssertEqual(decoded.assessmentMethod, .cooperTwelveMinute)
        let renumbered = ATHLTHWorkoutPhasePlacement.renumbered(
            decoded, sequence: 7
        )
        XCTAssertEqual(renumbered.assessmentMethod, .cooperTwelveMinute)
        XCTAssertEqual(renumbered.sequence, 7)

        let warmup = ATHLTHWorkoutPhasePlacement.relocatingSelection(
            at: 0, to: .warmup, in: [main]
        )
        XCTAssertEqual(warmup.count, 1)
        XCTAssertNil(warmup[0].assessmentMethod)
    }

    @MainActor
    func testPresetsAttachOnlyToOneMainTestStepAndNeverWarmup() throws {
        let cases: [(String, ATHLTHAssessmentMethod)] = [
            ("ASS-009", .threeMinuteAllOut),
            ("ASS-005", .cooperTwelveMinute),
            ("ASS-001", .sixMinuteRun),
            ("ASS-003", .distanceTimeTrial),
            ("ASS-006", .conconiStep),
            ("ASS-010", .lactateStep)
        ]
        for (id, expected) in cases {
            let source = try XCTUnwrap(
                ATHLTHZonedPlanLibrary.workouts.first { $0.id == id }
            )
            let blocks = ATHLTHZonedPlanLibrary.blocks(for: source)
            let marked = blocks.filter { $0.assessmentMethod != nil }
            XCTAssertEqual(marked.count, 1, id)
            XCTAssertEqual(marked.first?.assessmentMethod, expected, id)
            XCTAssertEqual(marked.first?.resolvedPhase, .main, id)
            XCTAssertTrue(blocks.filter { $0.resolvedPhase != .main }
                .allSatisfy { $0.assessmentMethod == nil }, id)
        }
        XCTAssertNil(ATHLTHAssessmentMethod.bundledTest(for: "ASS-007"))
        XCTAssertNil(ATHLTHAssessmentMethod.bundledTest(for: "ASS-008"))
    }

    func testSnapshotKeepsProfileButNeverARecordedResult() throws {
        let snapshot = ExerciseSnapshot(
            name: "Knebøy",
            instructions: ["Sett med god kontroll"],
            assessmentMethod: .estimatedOneRepMax,
            primaryMuscles: ["Quads"], equipment: ["Barbell"], imageURL: nil
        )
        let decoded = try JSONDecoder().decode(
            ExerciseSnapshot.self, from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(decoded.assessmentMethod, .estimatedOneRepMax)
        XCTAssertEqual(decoded.instructions, snapshot.instructions)
    }
}
