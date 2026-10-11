import Foundation
import XCTest
@testable import ATHLTH

final class ChallengeProposalFlowTests: XCTestCase {
    private func makeChallenge() -> ATHLTHChallenge {
        let owner = UUID()
        let friend = UUID()
        let rules = ATHLTHChallengeRules(
            scoring: .mostDistance,
            verificationPolicy: .verifiedRequired,
            targetDistanceMeters: nil,
            targetDurationSeconds: nil,
            timeBasis: .elapsed,
            route: nil,
            gpsRequired: false,
            minimumRouteMatchPercent: nil,
            exerciseName: nil,
            fixedWeightKilograms: nil,
            startsAt: Date(timeIntervalSince1970: 1_800_000_000),
            endsAt: Date(timeIntervalSince1970: 1_800_086_400),
            allowMultipleAttempts: true,
            lockRulesAtStart: true,
            meetup: nil
        )
        return ATHLTHChallenge(
            creatorID: owner,
            title: "Weekend challenge",
            sport: .walking,
            participants: [
                ChallengeParticipant(
                    userID: owner,
                    displayName: "Owner",
                    state: .creator
                ),
                ChallengeParticipant(
                    userID: friend,
                    displayName: "Friend",
                    state: .invited
                )
            ],
            rules: rules,
            visibility: .privateOnly
        )
    }

    func testChallengeProposalUsesIndependentSnapshot() throws {
        let original = makeChallenge()
        var proposed = original
        proposed.title = "Updated route"
        proposed.rules.summary = "A new description"
        let friendID = try XCTUnwrap(original.participants.last?.userID)
        let proposal = ChallengeChangeProposal(
            id: UUID(),
            challengerID: friendID,
            original: original,
            proposed: proposed,
            submittedAt: Date()
        )
        XCTAssertTrue(proposal.hasChanges)
        XCTAssertEqual(original.title, "Weekend challenge")
        XCTAssertEqual(proposal.original.title, "Weekend challenge")
        XCTAssertEqual(proposal.proposed.title, "Updated route")

        let decoded = try JSONDecoder().decode(
            ChallengeChangeProposal.self,
            from: JSONEncoder().encode(proposal)
        )
        XCTAssertEqual(decoded, proposal)
        let changed = ChallengeChangeDiff.rows(decoded)
        XCTAssertTrue(changed.contains(where: {
            $0.id == "title" &&
            $0.oldValue == "Weekend challenge" &&
            $0.newValue == "Updated route"
        }))
        XCTAssertTrue(changed.contains(where: { $0.id == "summary" }))
    }

    func testProposalResponseIsIndependentAndVersioned() throws {
        let challenge = makeChallenge()
        let response = ChallengeChangeProposalResponse(
            proposalID: UUID(),
            challengeID: challenge.id,
            accepted: false
        )
        let copied = try JSONDecoder().decode(
            ChallengeChangeProposalResponse.self,
            from: JSONEncoder().encode(response)
        )
        XCTAssertEqual(response, copied)
        XCTAssertFalse(copied.accepted)
    }
}
