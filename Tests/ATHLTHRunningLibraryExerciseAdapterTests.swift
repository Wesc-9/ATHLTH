import XCTest
@testable import ATHLTH

final class ATHLTHRunningLibraryExerciseAdapterTests: XCTestCase {
    private func libraryStep(_ title: String) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: title,
            exerciseSlug: "running", distanceMeters: nil, repetitions: 10,
            durationSeconds: nil, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .warmup
        )
    }

    func testRunningLibraryExerciseUsesExistingRunStep() {
        var original = libraryStep("Running")
        original.exerciseID = UUID()
        let converted = ATHLTHRunningLibraryExerciseAdapter.adapt(original)
        XCTAssertEqual(converted.kind, .run)
        XCTAssertEqual(converted.cardioActivity, .running)
        XCTAssertEqual(converted.durationSeconds, 600)
        XCTAssertNil(converted.setCount)
        XCTAssertNil(converted.repetitions)
        XCTAssertEqual(converted.exerciseID, original.exerciseID)
        XCTAssertEqual(converted.editorDragID, original.editorDragID)
    }
    func testTreadmillAndRunningAliasesAreClassifiedCorrectly() {
        for name in ["Treadmill", "Treadmill running", "Løping på tredemølle"] {
            let converted = ATHLTHRunningLibraryExerciseAdapter.adapt(libraryStep(name))
            XCTAssertEqual(converted.kind, .run)
            XCTAssertEqual(converted.cardioActivity, .running)
            XCTAssertEqual(converted.isIndoor, true)
            XCTAssertEqual(converted.treadmillInclinePercent, 0)
            XCTAssertEqual(converted.targetPaceSecondsPerKilometer, 360)
            XCTAssertNil(converted.repetitions)
        }

        for name in ["Running", "Løping", "Jogging", "Jogg"] {
            let converted = ATHLTHRunningLibraryExerciseAdapter.adapt(libraryStep(name))
            XCTAssertEqual(converted.kind, .run)
            XCTAssertEqual(converted.cardioActivity, .running)
            XCTAssertNil(converted.treadmillInclinePercent)
            XCTAssertNotEqual(converted.isIndoor, true)
        }
    }

    func testNeverConvertsStrengthOrGroupedExercises() {
        XCTAssertEqual(ATHLTHRunningLibraryExerciseAdapter.adapt(
            libraryStep("Squat")).kind, .exercise)
        var grouped = libraryStep("Running")
        grouped.groupID = UUID()
        XCTAssertEqual(ATHLTHRunningLibraryExerciseAdapter.adapt(
            grouped).kind, .exercise)
    }
}
