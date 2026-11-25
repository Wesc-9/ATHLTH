import XCTest
@testable import ATHLTH

final class ATHLTHAdminDirectoryPresentationTests: XCTestCase {
    func testLastSignInUsesActualTimestampAndNoInventedFallback() {
        let date = Date(timeIntervalSince1970: 1_795_000_000)
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.lastSignInLabel(date, norwegian: true),
            date.formatted(date: .abbreviated, time: .omitted)
        )
        XCTAssertEqual(ATHLTHAdminDirectoryPresentation.lastSignInLabel(nil, norwegian: true), "Ikke registrert")
        XCTAssertEqual(ATHLTHAdminDirectoryPresentation.lastSignInLabel(nil, norwegian: false), "Not recorded")
    }

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

    func testExpiredTrialIsNotPresentedAsActivePlus() {
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.subscriptionLabel(
                tier: "free", status: "trial_expired", norwegian: true
            ), "Utløpt prøveperiode"
        )
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.subscriptionLabel(
                tier: "athlth_plus", status: "trialing", norwegian: true
            ), "ATHLTH+ · Prøveperiode"
        )
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.subscriptionLabel(
                tier: "athlth_plus", status: "admin_grant", norwegian: true
            ), "ATHLTH+ · Tildelt"
        )
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.accountStatusTitle(
                "suspended", norwegian: true
            ), "Deaktivert"
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
