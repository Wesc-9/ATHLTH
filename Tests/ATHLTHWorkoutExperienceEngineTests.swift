import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutExperienceEngineTests: XCTestCase {
    private func mode(
        _ activity: WorkoutActivity,
        _ indoor: Bool?,
        gps: Bool = false
    ) -> ATHLTHWorkoutLocationMode {
        ATHLTHWorkoutExperienceEngine.locationMode(
            activity: activity,
            isIndoor: indoor,
            hasRecordedGPS: gps
        )
    }

    func testTreadmillAndIndoorRunningAlwaysUseVenueCheckIn() {
        XCTAssertEqual(mode(.running, true), .indoorCheckIn)
        XCTAssertEqual(mode(.walking, true), .indoorCheckIn)
        XCTAssertEqual(mode(.cycling, true), .indoorCheckIn)
        XCTAssertEqual(
            mode(.running, true, gps: true),
            .indoorCheckIn,
            "Incidental GPS data may never turn a treadmill session into an outdoor map"
        )
    }

    func testStrengthAndIndoorExerciseKindsUseSamePrivateCheckIn() {
        for activity in [
            WorkoutActivity.strength, .hiit, .rowing, .elliptical,
            .stairClimbing, .yoga, .coreTraining
        ] {
            XCTAssertEqual(mode(activity, true), .indoorCheckIn)
            XCTAssertEqual(mode(activity, nil), .indoorCheckIn)
        }
    }

    func testOutdoorGPSActivitiesAlwaysPreferARealSavedMap() {
        for activity in [
            WorkoutActivity.running, .walking, .cycling, .hiking, .swimming
        ] {
            XCTAssertEqual(
                mode(activity, false, gps: true),
                .recordedGPSMap
            )
            XCTAssertEqual(
                mode(activity, nil, gps: true),
                .recordedGPSMap
            )
        }
    }

    func testNoGpsRouteNeverCreatesFakeMapOrIndoorCheckIn() {
        for activity in [
            WorkoutActivity.running, .walking, .cycling, .hiking, .swimming
        ] {
            XCTAssertEqual(mode(activity, false), .missingGPS)
            XCTAssertEqual(mode(activity, nil), .missingGPS)
        }
        XCTAssertEqual(mode(.other, nil), .noLocation)
        XCTAssertEqual(mode(.strength, false), .noLocation)
        XCTAssertEqual(mode(.strength, false, gps: true), .recordedGPSMap)
    }

    func testLegacyPlaceEligibilityDelegatesToOneRuleEngine() {
        XCTAssertTrue(
            WorkoutActivity.strength.allowsTrainingPlaceCheckIn(isIndoor: nil)
        )
        XCTAssertTrue(
            WorkoutActivity.running.allowsTrainingPlaceCheckIn(isIndoor: true)
        )
        XCTAssertFalse(
            WorkoutActivity.running.allowsTrainingPlaceCheckIn(isIndoor: nil)
        )
        XCTAssertFalse(
            WorkoutActivity.strength.allowsTrainingPlaceCheckIn(isIndoor: false)
        )
    }
}
