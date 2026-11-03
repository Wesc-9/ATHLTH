import XCTest
@testable import ATHLTH

final class ATHLTHPlannedRunStepEditorTests: XCTestCase {
    func testReadOnlyRouteDistanceShowsActualRouteLength() {
        XCTAssertEqual(ATHLTHPlannedRunStepEditor.readOnlyRouteDistance(7_250),
                       "7" + Locale.current.decimalSeparator! + "25 km")
        XCTAssertEqual(ATHLTHPlannedRunStepEditor.readOnlyRouteDistance(450), "450 m")
    }

    func testOptionalRouteIDSurvivesExistingWorkoutSerialization() throws {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Selected route",
            exerciseSlug: nil, distanceMeters: 7_250, repetitions: nil,
            durationSeconds: nil, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )
        XCTAssertNil(block.routeID)
        let routeID = UUID()
        block.routeID = routeID
        let saved = try JSONEncoder().encode(block)
        let restored = try JSONDecoder().decode(WorkoutTemplateBlock.self, from: saved)
        XCTAssertEqual(restored.routeID, routeID)
        XCTAssertEqual(restored.distanceMeters, 7_250)
    }

    func testLegacyRunBlockWithoutRouteStillDecodes() throws {
        let old = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Free running",
            exerciseSlug: nil, distanceMeters: 1_000, repetitions: nil,
            durationSeconds: nil, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )
        let decoded = try JSONDecoder().decode(
            WorkoutTemplateBlock.self, from: JSONEncoder().encode(old)
        )
        XCTAssertNil(decoded.routeID)
    }

    func testTreadmillSpeedAndPaceUseSameStoredTarget() {
        XCTAssertEqual(ATHLTHPlannedTreadmillTargets.pace(forSpeed: 12), 300)
        XCTAssertEqual(ATHLTHPlannedTreadmillTargets.speed(forPace: 300), 12)
        XCTAssertEqual(ATHLTHPlannedTreadmillTargets.pace(forSpeed: 0), 3_600)
        XCTAssertEqual(ATHLTHPlannedTreadmillTargets.speed(forPace: 0), 25)
    }

    func testOutdoorAndIndoorRunUseIdenticalSpeedToPaceTargets() {
        // Switching the editor's display between km/t and min/km must not
        // change the stored target or the estimated training distance.
        let speedKmH = 12.0
        let pace = ATHLTHPlannedTreadmillTargets.pace(forSpeed: speedKmH)
        XCTAssertEqual(pace, 300, accuracy: 0.0001)
        XCTAssertEqual(
            ATHLTHPlannedTreadmillTargets.speed(forPace: pace),
            speedKmH, accuracy: 0.0001
        )

        var outdoor = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Outdoor running",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 1_200, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )
        outdoor.cardioActivity = .running
        outdoor.targetPaceSecondsPerKilometer = pace
        var indoor = outdoor
        indoor.title = "Indoor running"
        indoor.isIndoor = true
        var treadmill = indoor
        treadmill.treadmillInclinePercent = 1.0

        for run in [outdoor, indoor, treadmill] {
            XCTAssertEqual(
                ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(
                    for: [run]
                ) ?? -1,
                4.0, accuracy: 0.0001
            )
            XCTAssertEqual(
                ATHLTHPlannedWorkoutMetrics.commonPaceSecondsPerKilometer(
                    for: [run]
                ),
                300
            )
        }
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
