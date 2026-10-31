import XCTest
@testable import ATHLTH

final class ATHLTHPlannedRunStepEditorTests: XCTestCase {
    func testTreadmillSpeedAndPaceUseSameStoredTarget() {
        XCTAssertEqual(ATHLTHPlannedTreadmillTargets.pace(forSpeed: 12), 300)
        XCTAssertEqual(ATHLTHPlannedTreadmillTargets.speed(forPace: 300), 12)
        XCTAssertEqual(ATHLTHPlannedTreadmillTargets.pace(forSpeed: 0), 3_600)
        XCTAssertEqual(ATHLTHPlannedTreadmillTargets.speed(forPace: 0), 25)
    }

    func testRunBlockSupportsIndoorTreadmillMetadataInExistingModel() throws {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Løping",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 3723, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )
        block.isIndoor = true
        block.treadmillInclinePercent = 1.5
        block.targetPaceSecondsPerKilometer = 300
        block.targetHeartRateZone = 3
        block.targetEffortRPE = 6

        let decoded = try JSONDecoder().decode(
            WorkoutTemplateBlock.self, from: JSONEncoder().encode(block)
        )
        XCTAssertEqual(decoded.durationSeconds, 3723)
        XCTAssertEqual(decoded.treadmillInclinePercent, 1.5)
        XCTAssertEqual(decoded.targetPaceSecondsPerKilometer, 300)
        XCTAssertEqual(decoded.targetHeartRateZone, 3)
        XCTAssertEqual(decoded.targetEffortRPE, 6)
        XCTAssertEqual(decoded.isIndoor, true)
    }
}
