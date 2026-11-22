import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAdminPlusGrantTests: XCTestCase {
    func testRecipientSeesExactGrantDurationAndExpiryInNorwegian() {
        let canonical = "You have received ATHLTH+ for 30 days. Valid until 2026-12-22 14:15 UTC."
        XCTAssertEqual(
            ATHLTHPlusGrantNotificationCopy.title(norwegian: true),
            "Du har fått ATHLTH+"
        )
        XCTAssertEqual(
            ATHLTHPlusGrantNotificationCopy.message(canonical, norwegian: true),
            "Du har fått ATHLTH+ i 30 dager. Tilgangen varer til 2026-12-22 14:15 UTC."
        )
        XCTAssertEqual(
            ATHLTHPlusGrantNotificationCopy.message(canonical, norwegian: false),
            canonical
        )
    }

    func testUnlimitedPlusGiftShowsNoEndDate() {
        XCTAssertEqual(
            ATHLTHPlusGrantNotificationCopy.message(
                "You have received ATHLTH+ with no end date.", norwegian: true
            ),
            "Du har fått ATHLTH+ uten sluttdato."
        )
    }

    func testUnknownPlusGrantTextIsNotMisrepresented() {
        let unknown = "You have received ATHLTH+ for 400 days. Valid until tomorrow."
        XCTAssertEqual(
            ATHLTHPlusGrantNotificationCopy.message(unknown, norwegian: true),
            unknown
        )
    }

    func testComplimentaryGrantExpiresOnServerProvidedDate() {
        let future = Date().addingTimeInterval(24 * 3600)
        let past = Date().addingTimeInterval(-24 * 3600)
        XCTAssertTrue(BackendAdminPlusGrant(
            expiresAt: future, revokedAt: nil
        ).isActive)
        XCTAssertFalse(BackendAdminPlusGrant(
            expiresAt: past, revokedAt: nil
        ).isActive)
    }

    func testUnlimitedGrantCanStillBeRevoked() {
        XCTAssertTrue(BackendAdminPlusGrant(
            expiresAt: nil, revokedAt: nil
        ).isActive)
        XCTAssertFalse(BackendAdminPlusGrant(
            expiresAt: nil, revokedAt: Date()
        ).isActive)
    }

    func testGrantedPlusAccessIsNotAnAppStorePurchase() {
        let access = SubscriptionAccess(
            state: .paid, source: .serverVerified,
            currentPeriodEndsAt: Date().addingTimeInterval(3600)
        )
        XCTAssertTrue(access.hasPaidAccess)
        XCTAssertNil(access.productID)
        XCTAssertFalse(SubscriptionAccess(
            state: .paid, source: .serverVerified,
            currentPeriodEndsAt: Date().addingTimeInterval(-60)
        ).hasPaidAccess)
    }

    func testDirectoryDifferentiatesGrantedAccessFromExpiredTrial() {
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.subscriptionLabel(
                tier: "athlth_plus", status: "admin_grant", norwegian: true
            ),
            "ATHLTH+ · Tildelt"
        )
        XCTAssertEqual(
            ATHLTHAdminDirectoryPresentation.subscriptionLabel(
                tier: "free", status: "trial_expired", norwegian: true
            ),
            "Utløpt prøveperiode"
        )
    }
}
