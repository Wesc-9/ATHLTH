import XCTest
@testable import ATHLTH

final class ATHLTHPlannedWorkoutMetricsTests: XCTestCase {
    private func run(
        seconds: Double? = nil,
        meters: Double? = nil,
        pace: Double? = nil,
        indoor: Bool? = nil,
        incline: Double? = nil
    ) -> WorkoutTemplateBlock {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Running",
            exerciseSlug: nil, distanceMeters: meters,
            repetitions: nil, durationSeconds: seconds,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
        block.cardioActivity = .running
        block.targetPaceSecondsPerKilometer = pace
        block.isIndoor = indoor
        block.treadmillInclinePercent = incline
        return block
    }

    private func rest(seconds: Double, pace: Double? = nil) -> WorkoutTemplateBlock {
        var block = run(seconds: seconds, pace: pace)
        block.kind = .rest
        block.title = "Pause"
        return block
    }

    func testTreadmillTwentyMinutesAtTenKilometersPerHourIsAboutThreePointThreeKm() {
        let treadmill = run(
            seconds: 20 * 60, pace: 360, indoor: true, incline: 1
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(
                for: [treadmill]
            ) ?? -1,
            10.0 / 3,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.commonPaceSecondsPerKilometer(
                for: [treadmill]
            ), 360
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.runningLocation(for: [treadmill]),
            .treadmill
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.treadmillInclineRange(for: [treadmill]),
            1.0...1.0
        )
    }

    func testDistanceRecomputesWhenTimeOrTargetPaceChanges() {
        var step = run(seconds: 1_200, pace: 360)
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(for: [step]) ?? -1,
            10.0 / 3, accuracy: 0.0001
        )
        step.targetPaceSecondsPerKilometer = 300
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(for: [step]) ?? -1,
            4, accuracy: 0.0001
        )
        step.durationSeconds = 900
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(for: [step]) ?? -1,
            3, accuracy: 0.0001
        )
    }

    func testDifferentIntervalSpeedsAndPacedRecoveriesAreSummedIndividually() {
        let steps = [
            run(seconds: 240, pace: 300),
            rest(seconds: 60, pace: 600),
            run(seconds: 240, pace: 240),
            rest(seconds: 60, pace: 600)
        ]
        // 0.8 km + 0.1 km + 1.0 km + 0.1 km.
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(for: steps) ?? -1,
            2.0, accuracy: 0.0001
        )
        XCTAssertNil(
            ATHLTHPlannedWorkoutMetrics.commonPaceSecondsPerKilometer(for: steps)
        )
        XCTAssertTrue(ATHLTHPlannedWorkoutMetrics.hasVariablePace(for: steps))
    }

    func testCompactIntervalGroupExpandsBeforeEstimatingTotalDistance() {
        let group = UUID()
        var effort = run(seconds: 240, pace: 300)
        effort.groupID = group
        effort.groupKind = .intervals
        effort.groupRounds = 2
        var pause = rest(seconds: 60, pace: 600)
        pause.groupID = group
        pause.groupKind = .intervals
        pause.groupRounds = 2
        let original = [effort, pause]
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(for: original) ?? -1,
            1.7, accuracy: 0.0001
        )
        XCTAssertEqual(original.count, 2)
        XCTAssertEqual(original[0].groupRounds, 2)
    }

    func testExplicitDistanceAddsToKnownTimedDistance() {
        let steps = [
            run(meters: 5_000),
            run(seconds: 600, pace: 300),
            rest(seconds: 90)
        ]
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(for: steps) ?? -1,
            7.0, accuracy: 0.0001
        )
    }

    func testIncompleteOrInvalidSpeedNeverFabricatesDistance() {
        XCTAssertNil(ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(
            for: [run(seconds: 1_200)]
        ))
        XCTAssertNil(ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(
            for: [run(seconds: 1_200, pace: 360), run(seconds: 300)]
        ))
        XCTAssertNil(ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(
            for: [run(seconds: 1_200, pace: 0)]
        ))
        var active = rest(seconds: 60)
        active.activityTag = "active_recovery"
        XCTAssertNil(ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(
            for: [run(seconds: 1_200, pace: 360), active]
        ))
    }

    func testIndoorOutdoorAndMixedEnvironmentsAndInclineRange() {
        let outdoor = run(seconds: 600, pace: 360)
        let indoor = run(seconds: 600, pace: 360, indoor: true)
        let treadmill = run(
            seconds: 600, pace: 360, indoor: true, incline: 0
        )
        var uphill = treadmill
        uphill.treadmillInclinePercent = 2.5
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.runningLocation(for: [outdoor]),
            .outdoor
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.runningLocation(for: [indoor]),
            .indoor
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.runningLocation(for: [treadmill, uphill]),
            .treadmill
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.runningLocation(for: [outdoor, treadmill]),
            .mixed
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.treadmillInclineRange(
                for: [treadmill, uphill]
            ), 0...2.5
        )
    }

    func testPreviewEstimatesMixedRunTestWarmupAndWalkJogCooldown() throws {
        let previous = UserDefaults.standard.string(forKey: "settings.language")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "settings.language") }
            else { UserDefaults.standard.removeObject(forKey: "settings.language") }
        }
        UserDefaults.standard.set("nb", forKey: "settings.language")

        var warmup = run(seconds: 600)
        warmup.sourceIntensityZoneLabel = "Z1-Z2"
        warmup.targetHeartRatePercentMin = 50
        warmup.targetHeartRatePercentMax = 70
        var drills = run(seconds: 300)
        drills.title = "Driller"
        var assessment = run(seconds: 180)
        assessment.title = "3 min maksimaltest"
        assessment.targetHeartRateZone = 5
        var cooldown = run(seconds: 600)
        cooldown.title = "Gå, deretter rolig jogg"
        cooldown.targetHeartRateZone = 1

        let steps = [warmup, drills, assessment, cooldown]
        XCTAssertNil(ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(for: steps))
        let preview = try XCTUnwrap(ATHLTHPlannedWorkoutMetrics.previewDistance(for: steps))
        XCTAssertEqual(preview.kilometers,
                       600/420.0 + 300/360.0 + 180/270.0 + 600/600.0,
                       accuracy: 0.001)
        XCTAssertTrue(preview.usesEstimatedDistance)
        XCTAssertTrue(preview.usesAssumedPace)
        XCTAssertEqual(ATHLTHPlannedWorkoutMetrics.plannedHeartRateZoneRange(for: steps),
                       1...5)
        XCTAssertEqual(preview.averagePaceSecondsPerKilometer ?? -1,
                       1_680 / preview.kilometers, accuracy: 0.1)
    }

    func testAddingTargetPaceImmediatelyChangesPreviewWithoutMutatingInput() throws {
        var timed = run(seconds: 600)
        let original = timed
        let fallback = try XCTUnwrap(ATHLTHPlannedWorkoutMetrics.previewDistance(for: [timed]))
        XCTAssertEqual(fallback.kilometers, 600 / 360.0, accuracy: 0.0001)
        timed.targetPaceSecondsPerKilometer = 300
        let faster = try XCTUnwrap(ATHLTHPlannedWorkoutMetrics.previewDistance(for: [timed]))
        XCTAssertEqual(faster.kilometers, 2, accuracy: 0.0001)
        XCTAssertFalse(faster.usesAssumedPace)
        XCTAssertTrue(faster.usesEstimatedDistance)
        XCTAssertNil(ATHLTHPlannedWorkoutMetrics.commonPaceSecondsPerKilometer(for: [original]))
        XCTAssertEqual(ATHLTHPlannedWorkoutMetrics.commonPaceSecondsPerKilometer(for: [timed]), 300)
        XCTAssertNil(original.targetPaceSecondsPerKilometer)
    }

    func testPreviewWalkTreadmillAndStationaryPauseAreNotOvercounted() throws {
        var walk = run(seconds: 720)
        walk.cardioActivity = .walking
        let treadmill = run(seconds: 600, pace: 300, indoor: true, incline: 2)
        let resting = rest(seconds: 120)
        let preview = try XCTUnwrap(
            ATHLTHPlannedWorkoutMetrics.previewDistance(for: [walk, treadmill, resting])
        )
        XCTAssertEqual(preview.kilometers, 3.0, accuracy: 0.0001)
        XCTAssertTrue(preview.usesAssumedPace)
        XCTAssertEqual(ATHLTHPlannedWorkoutMetrics.runningLocation(for: [walk, treadmill]),
                       .mixed)
    }

    func testZoneRangePreservesOriginalMultiZoneAndMapsZ6ToS5() {
        var ranged = run(seconds: 600)
        ranged.sourceIntensityZoneLabel = "Z1-Z2"
        var high = run(seconds: 180)
        high.sourceIntensityZoneLabel = "Z4-Z6"
        XCTAssertEqual(ATHLTHPlannedWorkoutMetrics.plannedHeartRateZoneRange(for: [ranged, high]),
                       1...5)
        XCTAssertEqual(ATHLTHPlannedWorkoutMetrics.plannedHeartRateZoneRange(for: [high]),
                       4...5)
        ranged.sourceIntensityZoneLabel = nil
        ranged.targetHeartRatePercentMin = 60
        ranged.targetHeartRatePercentMax = 80
        XCTAssertEqual(ATHLTHPlannedWorkoutMetrics.plannedHeartRateZoneRange(for: [ranged]),
                       2...3)
    }

    func testNeverInventStrengthOrOpenEndedCardioDistances() {
        var strength = run(seconds: 900)
        strength.kind = .exercise
        XCTAssertNil(ATHLTHPlannedWorkoutMetrics.previewDistance(for: [strength]))
        XCTAssertNil(ATHLTHPlannedWorkoutMetrics.plannedHeartRateZoneRange(for: [strength]))
        let open = run()
        XCTAssertNil(ATHLTHPlannedWorkoutMetrics.previewDistance(for: [open]))
        let invalid = run(seconds: 600, pace: 0)
        XCTAssertNil(ATHLTHPlannedWorkoutMetrics.previewDistance(for: [invalid]))
    }

    func testIntervalRepeatsAndThreeStationaryRecoveriesKeepCorrectDistance() throws {
        let groupID = UUID()
        var main = run(seconds: 240, pace: 300)
        main.groupID = groupID
        main.groupKind = .intervals
        main.groupRounds = 4
        var rest = rest(seconds: 120)
        rest.groupID = groupID
        rest.groupKind = .intervals
        rest.groupRounds = 4
        let preview = try XCTUnwrap(
            ATHLTHPlannedWorkoutMetrics.previewDistance(for: [main, rest])
        )
        XCTAssertEqual(preview.kilometers, 3.2, accuracy: 0.0001)
        XCTAssertFalse(preview.usesAssumedPace)
    }


}
