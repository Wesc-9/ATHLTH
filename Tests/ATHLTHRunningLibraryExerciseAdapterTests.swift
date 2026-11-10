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

    func testProgressivePresetContainsIncreasingActualPaceTargets() {
        let steps = ATHLTHRunningExercisePreset.progressive.blocks(in: .main)
        XCTAssertEqual(steps.count, 3)
        XCTAssertEqual(steps.map(\.durationSeconds), [300, 300, 300])
        XCTAssertEqual(
            steps.compactMap(\.targetPaceSecondsPerKilometer),
            [420, 390, 360]
        )
        XCTAssertTrue(steps.allSatisfy { $0.kind == .run && $0.resolvedPhase == .main })
    }

    func testFartlekHasDifferentEffortLengthsAndRecoveries() {
        let steps = ATHLTHRunningExercisePreset.fartlek.blocks(in: .main)
        XCTAssertEqual(steps.count, 10)
        XCTAssertEqual(steps.enumerated().filter { $0.offset.isMultiple(of: 2) }
            .compactMap { $0.element.durationSeconds }, [60, 120, 180, 120, 60])
        XCTAssertEqual(steps.filter { $0.activityTag == "active_recovery" }.count, 5)
        XCTAssertEqual(steps.filter { $0.activityTag == "active_recovery" }
            .map(\.targetHeartRateZone), [2, 2, 2, 2, 2])
    }

    func testLongRecoveryAndPerformanceRunPresetsAreRealRunningSteps() {
        let long = ATHLTHRunningExercisePreset.longRun.blocks(in: .main)
        XCTAssertEqual(long.count, 1)
        XCTAssertEqual(long.first?.durationSeconds, 4_500)
        XCTAssertEqual(long.first?.targetHeartRateZone, 2)

        let recovery = ATHLTHRunningExercisePreset.recoveryRun.blocks(in: .cooldown)
        XCTAssertEqual(recovery.first?.targetHeartRateZone, 1)
        XCTAssertEqual(recovery.first?.durationSeconds, 1_500)

        let cooper = ATHLTHRunningExercisePreset.cooperTest.blocks(in: .main)
        XCTAssertEqual(cooper.first?.durationSeconds, 720)

        for (preset, meters) in [
            (ATHLTHRunningExercisePreset.oneKilometerTest, 1_000.0),
            (.fiveKilometerTest, 5_000.0),
            (.tenKilometerTest, 10_000.0)
        ] {
            let steps = preset.blocks(in: .main)
            XCTAssertEqual(steps.count, 1)
            XCTAssertEqual(steps.first?.kind, .run)
            XCTAssertEqual(steps.first?.distanceMeters, meters)
            XCTAssertNil(steps.first?.durationSeconds)
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
