import XCTest
@testable import ATHLTH

final class SubscriptionProductIdentifierTests: XCTestCase {
    // Must match App Store Connect, including the "paid" segment.
    @MainActor
    func testSubscriptionProductIdentifiersMatchAppStoreConnect() {
        XCTAssertEqual(
            SubscriptionStore.monthlyProductID,
            "com.wesc9.athlth.paid.monthly"
        )
        XCTAssertEqual(
            SubscriptionStore.yearlyProductID,
            "com.wesc9.athlth.paid.yearly"
        )
        XCTAssertEqual(
            SubscriptionStore.productIDs,
            Set([
                "com.wesc9.athlth.paid.monthly",
                "com.wesc9.athlth.paid.yearly"
            ])
        )
    }

    @MainActor
    func testBillingPeriodRecognizesBothRealProducts() {
        let monthly = SubscriptionAccess(
            state: .paid,
            source: .appStore,
            productID: SubscriptionStore.monthlyProductID
        )
        let yearly = SubscriptionAccess(
            state: .paid,
            source: .appStore,
            productID: SubscriptionStore.yearlyProductID
        )

        XCTAssertNotNil(monthly.billingPeriodTitle)
        XCTAssertNotNil(yearly.billingPeriodTitle)
    }
}
