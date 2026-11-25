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

    func testIndependentMessageInsertsDoNotShareIdentity() {
        XCTAssertNotEqual(message().id, message().id)
    }
}
