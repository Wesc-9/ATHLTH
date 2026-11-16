import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutInvitationPushRouteTests: XCTestCase {
    func testRemoteWorkoutInviteResolvesInboxWithAccountAndSession() {
        let sessionID = UUID()
        let recipientID = UUID()
        let eventID = UUID()
        let payload: [AnyHashable: Any] = [
            "athlth_kind": "workout_invite",
            "athlth_entity_type": "workout_session",
            "athlth_entity_id": sessionID.uuidString,
            "athlth_recipient_id": recipientID.uuidString,
            "athlth_event_id": eventID.uuidString
        ]
        let route = ATHLTHWorkoutInviteNotificationRoute.resolve(userInfo: payload)
        XCTAssertEqual(route?.workoutSessionID, sessionID)
        XCTAssertEqual(route?.recipientID, recipientID)
        XCTAssertEqual(route?.backendEventID, eventID)
    }

    func testLegacyWorkoutInviteWithoutRecipientStillOpensOwnInbox() {
        let sessionID = UUID()
        let route = ATHLTHWorkoutInviteNotificationRoute.resolve(userInfo: [
            "athlth_kind": "workout_invite",
            "athlth_entity_type": "workout_session",
            "athlth_entity_id": sessionID.uuidString
        ])
        XCTAssertEqual(route?.workoutSessionID, sessionID)
        XCTAssertNil(route?.recipientID)
    }

    func testOtherKindsNeverNavigateToWorkoutInvitation() {
        let sessionID = UUID().uuidString
        for kind in ["workout_invite_accepted", "message", "challenge_invite"] {
            XCTAssertNil(ATHLTHWorkoutInviteNotificationRoute.resolve(userInfo: [
                "athlth_kind": kind,
                "athlth_entity_type": "workout_session",
                "athlth_entity_id": sessionID
            ]))
        }
    }

    func testMalformedSessionOrEntityTypeDoesNotNavigate() {
        let id = UUID().uuidString
        XCTAssertNil(ATHLTHWorkoutInviteNotificationRoute.resolve(userInfo: [
            "athlth_kind": "workout_invite",
            "athlth_entity_type": "workout_session",
            "athlth_entity_id": "invalid"
        ]))
        XCTAssertNil(ATHLTHWorkoutInviteNotificationRoute.resolve(userInfo: [
            "athlth_kind": "workout_invite",
            "athlth_entity_type": "community_event",
            "athlth_entity_id": id
        ]))
    }
}
