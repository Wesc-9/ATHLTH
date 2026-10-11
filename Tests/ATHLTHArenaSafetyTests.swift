import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHArenaSafetyTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testDeletedMemberKeepsStableSlotAndEarnedPoints() throws {
        let slotID = UUID()
        let seriesID = UUID()
        let payload = """
        {
          "slot_id":"\(slotID.uuidString)",
          "series_id":"\(seriesID.uuidString)",
          "user_id":null,
          "response":"deleted",
          "points":7.5,
          "created_at":"2026-10-11T01:00:00Z"
        }
        """
        let row = try decoder().decode(
            ATHLTHArenaRemoteMember.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(row.id, slotID)
        XCTAssertNil(row.userID)
        XCTAssertTrue(row.isDeleted)
        XCTAssertEqual(row.points, 7.5)
    }

    func testReplacementOfAthletePreservesIndependentSlotID() throws {
        let slotID = UUID()
        let seriesID = UUID()
        let replacementUser = UUID()
        let payload = """
        {
          "slot_id":"\(slotID.uuidString)",
          "series_id":"\(seriesID.uuidString)",
          "user_id":"\(replacementUser.uuidString)",
          "response":"accepted",
          "points":7.5,
          "created_at":"2026-10-11T01:00:00Z"
        }
        """
        let row = try decoder().decode(
            ATHLTHArenaRemoteMember.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(row.id, slotID)
        XCTAssertEqual(row.userID, replacementUser)
        XCTAssertFalse(row.isDeleted)
        XCTAssertEqual(row.points, 7.5)
    }

    func testDeletedOrganizerDoesNotMakeSeriesUnparseable() throws {
        let id = UUID()
        let payload = """
        {
          "id":"\(id.uuidString)",
          "owner_id":null,
          "title":"Friends Arena",
          "scope":"friends",
          "scoring":"winner",
          "duration_days":14,
          "status":"draft"
        }
        """
        let row = try decoder().decode(
            ATHLTHArenaRemoteSeries.self,
            from: Data(payload.utf8)
        )
        XCTAssertNil(row.ownerID)
        XCTAssertEqual(row.id, id)
        XCTAssertEqual(row.scoring, .winner)
    }

    func testDeletedChatAuthorHasNoProfileID() throws {
        let payload = """
        {
          "id":"\(UUID().uuidString)",
          "series_id":"\(UUID().uuidString)",
          "sender_id":null,
          "body":"Melding fra slettet bruker",
          "created_at":"2026-10-11T01:00:00Z"
        }
        """
        let message = try decoder().decode(
            ATHLTHArenaRemoteMessage.self,
            from: Data(payload.utf8)
        )
        XCTAssertNil(message.senderID)
    }
}
