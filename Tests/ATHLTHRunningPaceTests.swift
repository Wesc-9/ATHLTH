import XCTest
@testable import ATHLTH

final class ATHLTHRunningPaceTests: XCTestCase {
    func testMeasuredFiveKilometersInFortyMinutesIsEightMinutesPerKilometer() {
        let pace = ATHLTHRunningPace.average(
            elapsedSeconds: 40 * 60,
            distanceMeters: 5_000
        )
        XCTAssertNotNil(pace)
        XCTAssertEqual(pace ?? 0, 480, accuracy: 0.001)
    }

    func testPaceMatchesRecordedTreadmillWorkoutWithFractionalKilometers() {
        // 39:43 / 5.02 km = about 7:55/km.
        let pace = ATHLTHRunningPace.average(
            elapsedSeconds: 39 * 60 + 43,
            distanceMeters: 5_020
        )
        XCTAssertEqual(pace ?? 0, 474.701, accuracy: 0.01)
    }

    func testUseActiveElapsedSecondsExcludingPausedTime() {
        let pace = ATHLTHRunningPace.average(
            elapsedSeconds: 30 * 60,
            distanceMeters: 4_000
        )
        XCTAssertEqual(pace ?? 0, 450, accuracy: 0.001)
    }

    func testNoDistanceMeansUnknownPaceRatherThanInventedSpeed() {
        XCTAssertNil(ATHLTHRunningPace.average(elapsedSeconds: 600, distanceMeters: 0))
        XCTAssertNil(ATHLTHRunningPace.average(elapsedSeconds: 0, distanceMeters: 250))
        XCTAssertNil(ATHLTHRunningPace.average(elapsedSeconds: 30, distanceMeters: 19))
        XCTAssertNil(ATHLTHRunningPace.average(elapsedSeconds: 600, distanceMeters: .nan))
        XCTAssertNil(ATHLTHRunningPace.average(elapsedSeconds: .infinity, distanceMeters: 250))
    }

    func testIPhoneIndoorPolicyDoesNotMisclassifyLegacyWorkouts() {
        XCTAssertFalse(ATHLTHPhoneRunEnvironmentPolicy.isIndoor(nil))
        XCTAssertFalse(ATHLTHPhoneRunEnvironmentPolicy.isIndoor(.outdoor))
        XCTAssertTrue(ATHLTHPhoneRunEnvironmentPolicy.isIndoor(.indoor))
        XCTAssertTrue(ATHLTHPhoneRunEnvironmentPolicy.isIndoor(.treadmill))
    }

    func testGPSPaceIsNeverAllowedIndoors() {
        XCTAssertNil(ATHLTHRunningPace.outdoorGPS(speedMetersPerSecond: 3, isOutdoor: false))
        XCTAssertNil(ATHLTHRunningPace.outdoorGPS(speedMetersPerSecond: 0, isOutdoor: false))
    }

    func testOutdoorGPSConversionAndOutlierFiltering() {
        // 10 km/h = 6:00 per kilometer.
        XCTAssertEqual(
            ATHLTHRunningPace.outdoorGPS(
                speedMetersPerSecond: 10 / 3.6,
                isOutdoor: true
            ) ?? 0,
            360,
            accuracy: 0.001
        )
        XCTAssertNil(ATHLTHRunningPace.outdoorGPS(speedMetersPerSecond: -1, isOutdoor: true))
        XCTAssertNil(ATHLTHRunningPace.outdoorGPS(speedMetersPerSecond: 20, isOutdoor: true))
        XCTAssertNil(ATHLTHRunningPace.outdoorGPS(speedMetersPerSecond: .nan, isOutdoor: true))
    }

    func testTreadmillSpeedTenMatchesOutdoorPaceAndDistance() {
        let saved = ATHLTHPlannedTreadmillTargets.pace(forSpeed: 10)
        XCTAssertEqual(saved, 360, accuracy: 0.0001)
        XCTAssertEqual(ATHLTHPlannedTreadmillTargets.speed(forPace: saved), 10, accuracy: 0.0001)
        XCTAssertEqual(ATHLTHRunningPace.outdoorGPS(
            speedMetersPerSecond: 10 / 3.6, isOutdoor: true
        ) ?? 0, saved, accuracy: 0.0001)
        XCTAssertEqual(ATHLTHRunningPace.manuallyEstimatedTreadmillDistance(
            speedKilometersPerHour: 10, durationSeconds: 1800
        ) ?? 0, 5000, accuracy: 0.0001)
    }

    func testIndoorRunningLivePaceUsesRealMeasuredDistanceAndActiveTime() {
        // Screenshot case: treadmill, ~15 minutes and 1.93 km with no GPS.
        let average = ATHLTHRunningPace.average(
            elapsedSeconds: 900, distanceMeters: 1_930
        )
        let display = ATHLTHRunningPace.displayPace(
            current: nil, average: average
        )
        XCTAssertEqual(display.secondsPerKilometer ?? 0,
                       466.32, accuracy: 0.1)
        XCTAssertTrue(display.isAverage)
    }

    func testOutdoorGpsPaceTakesPrecedenceOverRecordedAverage() {
        let display = ATHLTHRunningPace.displayPace(
            current: 310, average: 480
        )
        XCTAssertEqual(display.secondsPerKilometer, 310)
        XCTAssertFalse(display.isAverage)
    }

    func testInvalidGpsPaceFallsBackAndNeverUsesTreadmillTargetAsMeasurement() {
        let display = ATHLTHRunningPace.displayPace(
            current: .nan, average: 465
        )
        XCTAssertEqual(display.secondsPerKilometer, 465)
        XCTAssertTrue(display.isAverage)
        let unknown = ATHLTHRunningPace.displayPace(
            current: nil,
            average: ATHLTHRunningPace.average(
                elapsedSeconds: 180, distanceMeters: 0
            )
        )
        XCTAssertNil(unknown.secondsPerKilometer)
        XCTAssertFalse(unknown.isAverage)
    }

    func testPrescribedTreadmillIntervalPaceConvertsToActualBeltSelection() {
        XCTAssertEqual(ATHLTHTreadmillSpeedPolicy.kilometersPerHour(
            forPace: 300
        ), 12.0)
        XCTAssertEqual(ATHLTHBeltSpeedPolicy.speed(forPace: 300), 12.0)
        XCTAssertNil(ATHLTHTreadmillSpeedPolicy.kilometersPerHour(forPace: 0))
        XCTAssertNil(ATHLTHBeltSpeedPolicy.speed(forPace: .nan))
        XCTAssertNil(ATHLTHBeltSpeedPolicy.speed(forPace: 30))
    }

    func testActualBeltSpeedChangesAccumulateDistanceFromActiveSecond() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var workout = PhoneWorkout(
            walking: false, start: start,
            resumedAt: start, lastCheckpoint: start,
            runEnvironment: .treadmill
        )
        workout.setTreadmillSpeed(6, at: start)
        workout.setTreadmillSpeed(12, at: start.addingTimeInterval(60))
        workout.advanceTreadmillDistance(at: start.addingTimeInterval(120))

        XCTAssertEqual(workout.treadmillSpeedHistory?.count, 2)
        XCTAssertEqual(workout.treadmillSpeedHistory?.first?.activeElapsedSeconds ?? -1,
                       0, accuracy: 0.01)
        XCTAssertEqual(workout.treadmillSpeedHistory?.last?.activeElapsedSeconds ?? -1,
                       60, accuracy: 0.01)
        XCTAssertEqual(workout.distanceMeters, 300, accuracy: 0.01)
    }

    func testMetricAndImperialTreadmillModesConvertWithoutChangingSavedPace() {
        let saved = ATHLTHPlannedTreadmillTargets.pace(forSpeed: 10)
        let mph = ATHLTHPlannedTreadmillTargets.displaySpeed(10, measurement: .imperial)
        XCTAssertEqual(mph, 6.2137119, accuracy: 0.0001)
        XCTAssertEqual(ATHLTHPlannedTreadmillTargets.canonicalSpeed(
            mph, measurement: .imperial
        ), 10, accuracy: 0.0001)
        let minPerMile = ATHLTHPlannedTreadmillTargets.displayPace(
            saved, measurement: .imperial
        )
        XCTAssertEqual(minPerMile, 579.36384, accuracy: 0.001)
        XCTAssertEqual(ATHLTHPlannedTreadmillTargets.canonicalPace(
            minPerMile, measurement: .imperial
        ), saved, accuracy: 0.0001)
        XCTAssertEqual(MeasurementPreference.metric.runningPaceUnit, "min/km")
        XCTAssertEqual(MeasurementPreference.imperial.runningSpeedUnit, "mph")
    }
}
