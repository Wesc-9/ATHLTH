import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTournamentConversationTests: XCTestCase {
    func testDuelNeverCreatesAGroupConversation() {
        XCTAssertEqual(ATHLTHCompetitionCreationPolicy.minOpponents(.duel), 1)
        XCTAssertEqual(ATHLTHCompetitionCreationPolicy.minOpponents(.league), 2)
        XCTAssertEqual(ATHLTHCompetitionCreationPolicy.minOpponents(.cup), 2)
    }

    func testTournamentInvitationAndExerciseNotificationsOpenOneThread() {
        let id = UUID()
        let recipient = UUID()
        for kind in ["arena_invite", "arena_round", "arena_chat"] {
            let payload: [AnyHashable: Any] = [
                "athlth_kind": kind,
                "athlth_entity_type": "athlth_tournament",
                "athlth_entity_id": id.uuidString,
                "athlth_recipient_id": recipient.uuidString
            ]
            let route = ATHLTHTournamentPushRoute.resolve(userInfo: payload)
            XCTAssertEqual(route?.tournamentID, id)
            XCTAssertTrue(route?.isForAccount(recipient) ?? false)
            XCTAssertFalse(route?.isForAccount(UUID()) ?? true)
        }
    }

    func testNormalDuelAndDifferentEntitiesNeverOpenGroupChat() {
        let id = UUID()
        let duel: [AnyHashable: Any] = [
            "athlth_kind": "challenge_invite",
            "athlth_entity_type": "social_challenge",
            "athlth_entity_id": id.uuidString
        ]
        XCTAssertNil(ATHLTHTournamentPushRoute.resolve(userInfo: duel))

        let oldArena: [AnyHashable: Any] = [
            "athlth_kind": "arena_round",
            "athlth_entity_type": "arena_series",
            "athlth_entity_id": id.uuidString
        ]
        XCTAssertNil(ATHLTHTournamentPushRoute.resolve(userInfo: oldArena))
    }

    func testUnrecognizedNotificationsDoNotGetTournamentRoutes() {
        let data: [AnyHashable: Any] = [
            "athlth_kind": "group_message",
            "athlth_entity_type": "athlth_tournament",
            "athlth_entity_id": UUID().uuidString
        ]
        XCTAssertNil(ATHLTHTournamentPushRoute.resolve(userInfo: data))
    }
}
