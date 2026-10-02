import XCTest
@testable import ATHLTH

final class TrainingPlaceEligibilityTests: XCTestCase {
    func testOutdoorRunDoesNotAllowFitnessCenterCheckIn() {
        XCTAssertFalse(
            WorkoutActivity.running
                .allowsTrainingPlaceCheckIn(
                    isIndoor: false
                )
        )
    }

    func testIndoorTreadmillRunAllowsFitnessCenterCheckIn() {
        XCTAssertTrue(
            WorkoutActivity.running
                .allowsTrainingPlaceCheckIn(
                    isIndoor: true
                )
        )
    }

    func testUnknownRunDoesNotAssumeIndoor() {
        XCTAssertFalse(
            WorkoutActivity.running
                .allowsTrainingPlaceCheckIn(
                    isIndoor: nil
                )
        )
    }

    func testStrengthAllowsFitnessCenterCheckIn() {
        XCTAssertTrue(
            WorkoutActivity.strength
                .allowsTrainingPlaceCheckIn(
                    isIndoor: true
                )
        )
    }

    func testIndoorGymActivitiesAllowFitnessCenterCheckIn() {
        let activities: [WorkoutActivity] = [
            .hiit,
            .rowing,
            .elliptical,
            .stairClimbing,
            .yoga,
            .coreTraining
        ]

        for activity in activities {
            XCTAssertTrue(
                activity.allowsTrainingPlaceCheckIn(
                    isIndoor: true
                ),
                "\(activity.rawValue) should allow an indoor training place."
            )
        }
    }
}
