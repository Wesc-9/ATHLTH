import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlannedHeartRatePreviewTests: XCTestCase {
    func testSourcePercentTargetsProduceConcreteEstimatedBPM() {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "10K pace",
            exerciseSlug: nil, distanceMeters: 2_000,
            repetitions: nil, durationSeconds: nil,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
        block.sourceIntensityZoneLabel = "Z4"
        block.targetHeartRatePercentMin = 80
        block.targetHeartRatePercentMax = 90
        XCTAssertEqual(
            ATHLTHPlannedHeartRatePreview.expectedBPM(
                for: block, maximumBPM: 190
            ), 152...171
        )
        XCTAssertNil(
            ATHLTHPlannedHeartRatePreview.expectedBPM(
                for: block, maximumBPM: nil
            )
        )
    }

    func testSuggestedFourByFourZoneUsesConfiguredMaximumOnly() {
        var block = WorkoutTemplateBlock(sequence: 1, kind: .run, title: "Intervall",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil, durationSeconds: 240,
            targetWeightKilograms: nil, loadNote: nil, notes: nil, phase: .main)
        XCTAssertEqual(ATHLTHPlannedHeartRatePreview.expectedBPM(for: block, maximumBPM: 190, suggestedZones: 4...4), 152...171)
        XCTAssertEqual(ATHLTHPlannedHeartRatePreview.expectedBPM(for: block, maximumBPM: 190, suggestedZones: 1...2), 95...133)
        XCTAssertNil(ATHLTHPlannedHeartRatePreview.rangeText(for: block, maximumBPM: nil, suggestedZones: 4...4))
        block.targetHeartRateZone = 3
        XCTAssertEqual(ATHLTHPlannedHeartRatePreview.expectedBPM(for: block, maximumBPM: 190, suggestedZones: 4...4), 133...152)
    }

    func testImportPaceConversionUsesCorrectUnitsAndRejectsInvalidInput() throws {
        XCTAssertEqual(try XCTUnwrap(ATHLTHRunningImportPace.kilometersPerHour(from: "4:17", treadmill: false)), 3600 / 257.0, accuracy: 0.0001)
        XCTAssertEqual(ATHLTHRunningImportPace.kilometersPerHour(from: "14,5", treadmill: true), 14.5)
        XCTAssertEqual(ATHLTHRunningImportPace.text(for: 257, treadmill: false), "4:17")
        XCTAssertNil(ATHLTHRunningImportPace.kilometersPerHour(from: "4:60", treadmill: false))
        XCTAssertNil(ATHLTHRunningImportPace.kilometersPerHour(from: "14", treadmill: false))
        XCTAssertNil(ATHLTHRunningImportPace.kilometersPerHour(from: "4:17", treadmill: true))
    }

    func testSavedPersonalZoneUsesSharedZoneEngine() {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Intervals",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 240,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
        block.targetHeartRateZone = 4
        XCTAssertEqual(
            ATHLTHPlannedHeartRatePreview.expectedBPM(
                for: block, maximumBPM: 190
            ), ATHLTHHeartRateZones.range(for: 4, maximumBPM: 190)
        )
    }
}
