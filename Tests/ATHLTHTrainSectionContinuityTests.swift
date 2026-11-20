import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainSectionContinuityTests: XCTestCase {
    func testSameAccountRestoresTrainSection() {
        let user = UUID()
        for section in ["today", "plan", "progress"] {
            XCTAssertEqual(ATHLTHTrainSectionContinuityPolicy.restoredSection(
                section, persistedAccountID: user.uuidString,
                currentAccountID: user
            ), section)
        }
    }

    func testDifferentAthleteCannotInheritPreviousTrainSection() {
        let userA = UUID(), userB = UUID()
        XCTAssertEqual(ATHLTHTrainSectionContinuityPolicy.restoredSection(
            "plan", persistedAccountID: userA.uuidString,
            currentAccountID: userB
        ), "today")
    }

    func testLegacyUnownedOrUnknownSectionDefaultsToToday() {
        let user = UUID()
        XCTAssertEqual(ATHLTHTrainSectionContinuityPolicy.restoredSection(
            "progress", persistedAccountID: "",
            currentAccountID: user
        ), "today")
        XCTAssertEqual(ATHLTHTrainSectionContinuityPolicy.restoredSection(
            "unknown", persistedAccountID: user.uuidString,
            currentAccountID: user
        ), "today")
    }
}
