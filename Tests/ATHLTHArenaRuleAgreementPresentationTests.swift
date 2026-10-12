import Foundation
import XCTest
@testable import ATHLTH

/// Rule approvals precede Arena scoring, but never award points or
/// substitute for unanimous approval of the eventual round result.
final class ATHLTHArenaRuleAgreementPresentationTests: XCTestCase {
    private let sender = UUID()
    private let recipient = UUID()
    private let one = UUID()
    private let two = UUID()

    private func approval(_ round: UUID, _ user: UUID)
        -> ATHLTHArenaRemoteApproval {
        ATHLTHArenaRemoteApproval(roundID: round, userID: user)
    }

    func testBothAthletesMustApproveEveryRound() {
        let approvals = [
            approval(one, sender),
            approval(one, recipient),
            approval(two, sender)
        ]
        XCTAssertEqual(ATHLTHArenaRuleAgreementPresentation.agreedCount(
            roundIDs: [one, two],
            acceptedUserIDs: [sender, recipient],
            pendingInvitations: 0,
            approvals: approvals
        ), 1)
        XCTAssertFalse(ATHLTHArenaRuleAgreementPresentation.allAgreed(
            roundIDs: [one, two],
            acceptedUserIDs: [sender, recipient],
            pendingInvitations: 0,
            approvals: approvals
        ))
    }

    func testFullyApprovedRulesCanBeDisplayedWithoutAwardingPoints() {
        let approvals = [
            approval(one, sender),
            approval(one, recipient),
            approval(two, sender),
            approval(two, recipient)
        ]
        XCTAssertTrue(ATHLTHArenaRuleAgreementPresentation.allAgreed(
            roundIDs: [one, two],
            acceptedUserIDs: [sender, recipient],
            pendingInvitations: 0,
            approvals: approvals
        ))
    }

    func testPendingInvitationsNeverLookLikeFullyAgreedCompetition() {
        let approvals = [
            approval(one, sender),
            approval(one, recipient)
        ]
        XCTAssertEqual(ATHLTHArenaRuleAgreementPresentation.agreedCount(
            roundIDs: [one],
            acceptedUserIDs: [sender, recipient],
            pendingInvitations: 1,
            approvals: approvals
        ), 0)
    }

    func testSingleAthleteCannotApproveCompetitionAlone() {
        XCTAssertFalse(ATHLTHArenaRuleAgreementPresentation.allAgreed(
            roundIDs: [one],
            acceptedUserIDs: [sender],
            pendingInvitations: 0,
            approvals: [approval(one, sender)]
        ))
    }

    func testOldOrUnknownVotersDoNotCountAsAcceptedAthletes() {
        let unknownUser = UUID()
        XCTAssertFalse(ATHLTHArenaRuleAgreementPresentation.allAgreed(
            roundIDs: [one],
            acceptedUserIDs: [sender, recipient],
            pendingInvitations: 0,
            approvals: [approval(one, sender), approval(one, unknownUser)]
        ))
    }

    func testDuplicatesAndEmptyRulesDoNotInflateAgreement() {
        let approvals = [
            approval(one, sender), approval(one, sender),
            approval(one, recipient)
        ]
        XCTAssertEqual(ATHLTHArenaRuleAgreementPresentation.agreedCount(
            roundIDs: [one, one],
            acceptedUserIDs: [sender, recipient],
            pendingInvitations: 0,
            approvals: approvals
        ), 1)
        XCTAssertFalse(ATHLTHArenaRuleAgreementPresentation.allAgreed(
            roundIDs: [],
            acceptedUserIDs: [sender, recipient],
            pendingInvitations: 0,
            approvals: approvals
        ))
    }
}
