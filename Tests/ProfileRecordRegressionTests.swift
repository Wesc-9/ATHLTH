import XCTest
@testable import ATHLTH

final class ProfileRecordRegressionTests:
    XCTestCase {
    func testExpandedRunningRecordDistances() {
        XCTAssertEqual(
            HealthPersonalRecordKind
                .fastest400M
                .targetDistanceMeters ?? 0,
            400
        )
        XCTAssertEqual(
            HealthPersonalRecordKind
                .fastest800M
                .targetDistanceMeters ?? 0,
            800
        )
        XCTAssertEqual(
            HealthPersonalRecordKind
                .fastest3K
                .targetDistanceMeters ?? 0,
            3_000
        )
        XCTAssertEqual(
            HealthPersonalRecordKind
                .fastest15K
                .targetDistanceMeters ?? 0,
            15_000
        )
        XCTAssertEqual(
            HealthPersonalRecordKind
                .fastest10Mile
                .targetDistanceMeters ?? 0,
            16_093.44,
            accuracy: 0.01
        )
    }

    func testExpandedRunningRecordsStayInRunningGroup() {
        let kinds: [ProfileFeaturedRecordKind] = [
            .fastest400M,
            .fastest800M,
            .fastest3K,
            .fastest15K,
            .fastest10Mile
        ]

        XCTAssertTrue(
            kinds.allSatisfy {
                $0.group == .running
            }
        )
    }

    func testProfileShowcaseStillUsesFourSlots() {
        XCTAssertEqual(
            ProfileFeaturedRecordKind
                .showcaseLimit,
            4
        )
    }

    func testAllHealthBackedProfileRecordsMapToHealthKind() {
        let healthBacked =
            ProfileFeaturedRecordKind
                .allCases
                .filter {
                    $0.group == .running ||
                    $0.group == .appleHealth ||
                    $0 ==
                        .longestStrengthWorkout
                }

        XCTAssertTrue(
            healthBacked.allSatisfy {
                $0.healthKind != nil
            }
        )
    }
}
