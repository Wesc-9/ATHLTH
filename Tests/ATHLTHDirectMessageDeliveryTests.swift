import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHDirectMessageDeliveryTests: XCTestCase {
    private func message(id: UUID = UUID()) -> DirectMessageInsert {
        DirectMessageInsert(id: id, conversationID: UUID(), senderID: UUID(),
            recipientID: UUID(), body: "Hei", attachmentKind: nil,
            attachmentTitle: nil, attachmentSubtitle: nil, attachmentPayload: nil,
            shareVersion: 1, sourceObjectID: nil, sourceOwnerID: nil)
    }

    func testExplicitRetryIDIsEncodedInInsert() throws {
        let id = UUID()
        let insert = message(id: id)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(insert)) as? [String: Any])
        XCTAssertEqual((json["id"] as? String).flatMap(UUID.init(uuidString:)), id)
        XCTAssertEqual((json["conversation_id"] as? String).flatMap(UUID.init(uuidString:)), insert.conversationID)
        XCTAssertEqual((json["sender_id"] as? String).flatMap(UUID.init(uuidString:)), insert.senderID)
        XCTAssertEqual((json["recipient_id"] as? String).flatMap(UUID.init(uuidString:)), insert.recipientID)
        XCTAssertEqual(json["body"] as? String, "Hei")
    }

    func testPushInvalidatesOnlyTheExactAccountAndConversation() {
        let owner = UUID(), thread = UUID()
        var payload: [AnyHashable: Any] = [
            "athlth_entity_type": "direct_conversation",
            "athlth_recipient_id": owner.uuidString.lowercased(),
            "athlth_entity_id": thread.uuidString
        ]
        XCTAssertTrue(ATHLTHDirectMessageRefreshPolicy.matches(payload, owner: owner, conversation: thread))
        XCTAssertFalse(ATHLTHDirectMessageRefreshPolicy.matches(payload, owner: UUID(), conversation: thread))
        XCTAssertFalse(ATHLTHDirectMessageRefreshPolicy.matches(payload, owner: owner, conversation: UUID()))
        payload["athlth_entity_type"] = "community_group"
        XCTAssertFalse(ATHLTHDirectMessageRefreshPolicy.matches(payload, owner: owner, conversation: thread))
        payload["athlth_entity_type"] = "direct_conversation"
        payload.removeValue(forKey: "athlth_recipient_id")
        XCTAssertFalse(ATHLTHDirectMessageRefreshPolicy.matches(payload, owner: owner, conversation: thread))
    }

    func testRealtimePollingFallbackIsImmediateOnDisconnect() {
        XCTAssertTrue(ATHLTHDirectMessageRefreshPolicy.shouldPoll(realtimeConnected: false, elapsed: 0))
        XCTAssertFalse(ATHLTHDirectMessageRefreshPolicy.shouldPoll(realtimeConnected: true, elapsed: 4))
        XCTAssertFalse(ATHLTHDirectMessageRefreshPolicy.shouldPoll(realtimeConnected: true, elapsed: 15.9))
        XCTAssertTrue(ATHLTHDirectMessageRefreshPolicy.shouldPoll(realtimeConnected: true, elapsed: 16))
        XCTAssertTrue(ATHLTHDirectMessageRefreshPolicy.shouldPoll(realtimeConnected: true, elapsed: -1))
        XCTAssertTrue(ATHLTHDirectMessageRefreshPolicy.shouldPoll(realtimeConnected: true, elapsed: .nan))
    }

    func testIndependentMessageInsertsDoNotShareIdentity() {
        XCTAssertNotEqual(message().id, message().id)
    }
}
