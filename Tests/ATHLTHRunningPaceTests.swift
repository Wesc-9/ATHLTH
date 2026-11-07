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
