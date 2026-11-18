import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAdminPlusGrantTests: XCTestCase {
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
