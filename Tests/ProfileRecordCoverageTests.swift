import XCTest
@testable import ATHLTH

final class ProfileRecordCoverageTests:
    XCTestCase {
    func testEveryAppleHealthPersonalRecordIsAvailableOnProfile() {
        let exposed =
            Set(
                ProfileFeaturedRecordKind
                    .allCases
                    .compactMap(
                        \.healthKind
                    )
            )

        XCTAssertEqual(
            exposed,
            Set(
                HealthPersonalRecordKind
                    .allCases
            )
        )
    }

    func testProfileRecordGroupsRemainSeparated() {
        XCTAssertTrue(
            ProfileFeaturedRecordKind
                .allCases
                .contains {
                    $0.group == .running
                }
        )
        XCTAssertTrue(
            ProfileFeaturedRecordKind
                .allCases
                .contains {
                    $0.group == .strength
                }
        )
        XCTAssertTrue(
            ProfileFeaturedRecordKind
                .allCases
                .contains {
                    $0.group == .appleHealth
                }
        )
    }
}
