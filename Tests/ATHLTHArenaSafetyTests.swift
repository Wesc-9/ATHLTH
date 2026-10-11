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
    private func nextAction(
        status: String = "draft",
        response: String? = "accepted",
        organizer: Bool = false,
        rounds: [UUID] = [UUID()],
        approved: Set<UUID> = [],
        allApproved: Bool = false,
        pendingInvites: Int = 0,
        acceptedCount: Int = 2,
        hasRoute: Bool = false,
        pastDeadline: Bool = false
    ) -> ATHLTHArenaNextAction? {
        ATHLTHArenaNextAction.resolve(
            status: status,
            response: response,
            isOrganizer: organizer,
            roundIDs: rounds,
            personallyApproved: approved,
            allRulesApproved: allApproved,
            pendingInvites: pendingInvites,
            acceptedCount: acceptedCount,
            hasRoute: hasRoute,
            deadlinePassed: pastDeadline
        )
    }

    func testArenaNextActionPrioritizesInvitationAndDoesNotShowForOutsiders() {
        XCTAssertEqual(
            nextAction(response: "invited", organizer: true, rounds: []),
            .respondToInvite
        )
        XCTAssertNil(nextAction(response: nil))
        XCTAssertNil(nextAction(response: "declined"))
    }

    func testArenaNextActionCreatorSetsUpFirstRound() {
        XCTAssertEqual(
            nextAction(organizer: true, rounds: []), .addRound
        )
        XCTAssertEqual(
            nextAction(organizer: false, rounds: []), .waitingForRules
        )
    }

    func testArenaNextActionRequiresPersonalRuleApprovalBeforeStart() {
        let round = UUID()
        XCTAssertEqual(
            nextAction(
                organizer: true,
                rounds: [round],
                approved: [],
                allApproved: true
            ),
            .approveRule(round)
        )
        XCTAssertEqual(
            nextAction(
                organizer: true,
                rounds: [round],
                approved: [round],
                allApproved: true,
                pendingInvites: 1
            ),
            .waitingForInvites
        )
        XCTAssertEqual(
            nextAction(
                organizer: true,
                rounds: [round],
                approved: [round],
                allApproved: false
            ),
            .waitingForRules
        )
    }

    func testArenaNextActionOnlyOrganizerMaySeeStartPrompt() {
        let round = UUID()
        XCTAssertEqual(
            nextAction(
                organizer: true,
                rounds: [round],
                approved: [round],
                allApproved: true
            ),
            .startSeries
        )
        XCTAssertEqual(
            nextAction(
                organizer: false,
                rounds: [round],
                approved: [round],
                allApproved: true
            ),
            .waitingForRules
        )
    }

    func testArenaNextActionDoesNotCallAnExpiredSeriesActive() {
        XCTAssertEqual(
            nextAction(status: "active", hasRoute: true), .runRoute
        )
        XCTAssertEqual(
            nextAction(status: "active", hasRoute: false), .compete
        )
        XCTAssertEqual(
            nextAction(
                status: "active", hasRoute: true, pastDeadline: true
            ),
            .reviewScores
        )
        XCTAssertEqual(
            nextAction(status: "completed"), .finalStandings
        )
        XCTAssertNil(nextAction(status: "cancelled"))
    }

}
