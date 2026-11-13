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
