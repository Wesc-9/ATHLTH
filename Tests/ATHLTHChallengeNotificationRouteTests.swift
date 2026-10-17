import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHChallengeNotificationRouteTests: XCTestCase {
    func testPersonalChallengeReminderRoutesByIDWithoutKind() {
        let id = UUID()
        let userInfo: [AnyHashable: Any] = [
            "athlthChallengeID": id.uuidString
        ]
        XCTAssertEqual(
            ATHLTHChallengeNotificationRoute.resolve(userInfo: userInfo),
            .personal(id)
        )
    }

    func testOfficialWeeklyReminderRoutesToWeeklyChallenge() {
        let id = UUID()
        let userInfo: [AnyHashable: Any] = [
            "athlthOfficialWeeklyChallengeID": id.uuidString
        ]
        XCTAssertEqual(
            ATHLTHChallengeNotificationRoute.resolve(userInfo: userInfo),
            .officialWeekly(id)
        )
    }

    func testWeeklyIDIsPreferredOverPersonalChallengeID() {
        let weeklyID = UUID()
        let personalID = UUID()
        let userInfo: [AnyHashable: Any] = [
            "athlthOfficialWeeklyChallengeID": weeklyID.uuidString,
            "athlthChallengeID": personalID.uuidString
        ]
        XCTAssertEqual(
            ATHLTHChallengeNotificationRoute.resolve(userInfo: userInfo),
            .officialWeekly(weeklyID)
        )
    }

    func testUnknownAndMalformedNotificationDoesNotOpenChallenge() {
        XCTAssertNil(
            ATHLTHChallengeNotificationRoute.resolve(
                userInfo: ["athlth_kind": "message"]
            )
        )
        XCTAssertNil(
            ATHLTHChallengeNotificationRoute.resolve(
                userInfo: ["athlthChallengeID": "invalid"]
            )
        )
        XCTAssertNil(
            ATHLTHChallengeNotificationRoute.resolve(
                userInfo: ["athlthOfficialWeeklyChallengeID": ""]
            )
        )
    }

    func testDistinctDestinationsForTheSameID() {
        let id = UUID()
        XCTAssertNotEqual(
            ATHLTHChallengeNotificationRoute.personal(id).id,
            ATHLTHChallengeNotificationRoute.officialWeekly(id).id
        )
    }
}
