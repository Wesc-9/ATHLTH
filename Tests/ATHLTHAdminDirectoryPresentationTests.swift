import XCTest
@testable import ATHLTH

final class ATHLTHAdminDirectoryPresentationTests: XCTestCase {
    func testPlusTierIsHumanReadableAndNotAValidationBadge() {
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.planTitle(
                "athlth_plus", norwegian: true
            ),
            "ATHLTH+"
        )
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.plan(
                for: "athlth_plus"
            ),
            .plus
        )
    }

    func testFreeTierAndUnknownValuesStayAccurate() {
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.planTitle(
                "free", norwegian: true
            ),
            "Gratis"
        )
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.planTitle(
                "free", norwegian: false
            ),
            "Free"
        )
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.planTitle(
                "legacy_value", norwegian: true
            ),
            "Ukjent abonnement"
        )
    }

    func testRolesUseNorwegianLabels() {
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.roleTitle(
                "admin", norwegian: true
            ),
            "Administrator"
        )
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.roleTitle(
                "user", norwegian: true
            ),
            "Bruker"
        )
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.roleTitle(
                "owner", norwegian: true
            ),
            "Eier"
        )
    }

    func testNameAndInitialsHaveSafeFallbacks() {
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.displayName(
                "  ", username: "testing"
            ),
            "testing"
        )
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.initials(
                "Kari Nordmann", username: "kari"
            ),
            "KN"
        )
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.initials(
                nil, username: nil
            ),
            "?"
        )
    }
}
