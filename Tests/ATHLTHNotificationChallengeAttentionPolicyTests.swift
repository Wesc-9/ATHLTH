import XCTest
@testable import ATHLTH

final class ATHLTHNotificationChallengeAttentionPolicyTests: XCTestCase {
    func testCancelledChallengeNeverRequiresAttention() {
        XCTAssertFalse(ATHLTHNotificationChallengeAttentionPolicy.requiresResponse(
            status: .cancelled,
            participantState: .invited,
            expiredWithoutOpponent: false
        ))
    }

    func testCompletedChallengeNeverRequiresAttention() {
        XCTAssertFalse(ATHLTHNotificationChallengeAttentionPolicy.requiresResponse(
            status: .completed,
            participantState: .invited,
            expiredWithoutOpponent: false
        ))
    }

    func testDraftChallengeNeverRequiresAttention() {
        XCTAssertFalse(ATHLTHNotificationChallengeAttentionPolicy.requiresResponse(
            status: .draft,
            participantState: .invited,
            expiredWithoutOpponent: false
        ))
    }

    func testPendingRecipientChallengeInviteStillRequiresAttention() {
        XCTAssertTrue(ATHLTHNotificationChallengeAttentionPolicy.requiresResponse(
            status: .invited,
            participantState: .invited,
            expiredWithoutOpponent: false
        ))
    }

    func testPendingInviteStillRequiresAttentionDuringUpcomingChallenge() {
        XCTAssertTrue(ATHLTHNotificationChallengeAttentionPolicy.requiresResponse(
            status: .upcoming,
            participantState: .invited,
            expiredWithoutOpponent: false
        ))
    }

    func testAcceptedDeclinedAndWithdrawnInvitesAreNoLongerActionable() {
        for state in [ChallengeParticipantState.accepted, .declined, .withdrawn, .creator] {
            XCTAssertFalse(ATHLTHNotificationChallengeAttentionPolicy.requiresResponse(
                status: .invited,
                participantState: state,
                expiredWithoutOpponent: false
            ))
        }
        XCTAssertFalse(ATHLTHNotificationChallengeAttentionPolicy.requiresResponse(
            status: .invited,
            participantState: nil,
            expiredWithoutOpponent: false
        ))
    }

    func testExpiredUnacceptedChallengeNeverRequiresAttention() {
        XCTAssertFalse(ATHLTHNotificationChallengeAttentionPolicy.requiresResponse(
            status: .invited,
            participantState: .invited,
            expiredWithoutOpponent: true
        ))
    }
}
