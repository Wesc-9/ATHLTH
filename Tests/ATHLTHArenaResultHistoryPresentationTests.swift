import Foundation
import XCTest
@testable import ATHLTH

/// Timeline is presentation-only; scores are never inferred from proposals.
final class ATHLTHArenaResultHistoryPresentationTests: XCTestCase {
    private let seriesID = UUID()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func result(
        roundID: UUID,
        status: String,
        age: TimeInterval,
        id: UUID = UUID()
    ) -> ATHLTHArenaRoundResult {
        ATHLTHArenaRoundResult(
            id: id,
            seriesID: seriesID,
            roundID: roundID,
            proposedBy: UUID(),
            rankedSlots: [UUID(), UUID()],
            evidenceNote: "Participant-reported result",
            status: status,
            createdAt: start.addingTimeInterval(-age)
        )
    }

    func testHistoryShowsRecentProposalsInDescendingOrder() {
        let roundID = UUID()
        let old = result(roundID: roundID, status: "rejected", age: 300)
        let new = result(roundID: roundID, status: "pending", age: 5)
        let middle = result(roundID: roundID, status: "approved", age: 100)
        let list = ATHLTHArenaResultHistoryPresentation.recent(
            [old, new, middle],
            for: [roundID]
        )
        XCTAssertEqual(list.map(\.id), [new.id, middle.id, old.id])
    }

    func testOnlyRoundsFromVisibleCompetitionAreIncluded() {
        let roundID = UUID()
        let mine = result(roundID: roundID, status: "pending", age: 50)
        let other = result(roundID: UUID(), status: "approved", age: 1)
        let history = ATHLTHArenaResultHistoryPresentation.recent(
            [other, mine],
            for: [roundID]
        )
        XCTAssertEqual(history.map(\.id), [mine.id])
    }

    func testOlderRejectedProposalRemainsVisibleInHistory() {
        let roundID = UUID()
        let rejected = result(roundID: roundID, status: "rejected", age: 200)
        let approved = result(roundID: roundID, status: "approved", age: 5)
        let history = ATHLTHArenaResultHistoryPresentation.recent(
            [rejected, approved],
            for: [roundID]
        )
        XCTAssertEqual(history.map(\.id), [approved.id, rejected.id])
    }

    func testHistoryRespectsLimitWithoutHidingRoundVotes() {
        let roundID = UUID()
        let entries = (0..<8).map {
            result(roundID: roundID, status: "pending", age: Double($0))
        }
        XCTAssertEqual(
            ATHLTHArenaResultHistoryPresentation.recent(
                entries, for: [roundID]
            ).count, 4
        )
        XCTAssertEqual(
            ATHLTHArenaResultHistoryPresentation.recent(
                entries, for: [roundID], limit: 0
            ).count, 0
        )
    }

    func testStatusLabelsNeverInferServerApproval() {
        let state = ATHLTHArenaResultHistoryPresentation.State.self
        XCTAssertEqual(state.resolve("approved"), .approved)
        XCTAssertEqual(state.resolve("pending"), .pending)
        XCTAssertEqual(state.resolve("rejected"), .rejected)
        XCTAssertEqual(state.resolve("expired"), .expired)
        XCTAssertEqual(state.resolve("unknown"), .unresolved)
        XCTAssertEqual(state.resolve(""), .unresolved)
    }

    func testExpandedHistoryShowsAllVisibleProposals() {
        let roundID = UUID()
        let rows = (0..<9).map {
            result(roundID: roundID, status: "rejected", age: Double($0))
        }
        let recent = ATHLTHArenaResultHistoryPresentation.recent(
            rows, for: [roundID]
        )
        let full = ATHLTHArenaResultHistoryPresentation.recent(
            rows, for: [roundID], limit: rows.count
        )
        XCTAssertEqual(recent.count, 4)
        XCTAssertEqual(full.count, 9)
        XCTAssertEqual(
            Set(full.map(\.id)),
            Set(rows.map(\.id))
        )
    }

    func testApprovedVotesCountOnlyUniqueEligibleAthletes() {
        let resultID = UUID()
        let first = UUID()
        let second = UUID()
        let removed = UUID()
        let votes: [ATHLTHArenaRoundResultVote] = [
            .init(resultID: resultID, userID: first, accepted: true),
            .init(resultID: resultID, userID: first, accepted: true),
            .init(resultID: resultID, userID: second, accepted: false),
            .init(resultID: resultID, userID: removed, accepted: true),
            .init(resultID: UUID(), userID: second, accepted: true)
        ]
        XCTAssertEqual(
            ATHLTHArenaResultHistoryPresentation.approvalCount(
                resultID: resultID,
                eligibleIDs: [first, second],
                votes: votes
            ),
            1
        )
    }

    func testOnlyPendingEligibleUnvotedResultsRequestMyApproval() {
        let roundID = UUID()
        let viewerID = UUID()
        let outsiderID = UUID()
        let pending = result(roundID: roundID, status: "pending", age: 1)
        let approved = result(roundID: roundID, status: "approved", age: 1)
        let otherVote = ATHLTHArenaRoundResultVote(
            resultID: UUID(), userID: viewerID, accepted: true
        )
        XCTAssertTrue(
            ATHLTHArenaResultHistoryPresentation.needsYourVote(
                result: pending,
                viewerID: viewerID,
                eligibleIDs: [viewerID],
                votes: [otherVote]
            )
        )
        XCTAssertFalse(
            ATHLTHArenaResultHistoryPresentation.needsYourVote(
                result: pending,
                viewerID: outsiderID,
                eligibleIDs: [viewerID],
                votes: []
            )
        )
        XCTAssertFalse(
            ATHLTHArenaResultHistoryPresentation.needsYourVote(
                result: approved,
                viewerID: viewerID,
                eligibleIDs: [viewerID],
                votes: []
            )
        )
        let rejectedVote = ATHLTHArenaRoundResultVote(
            resultID: pending.id, userID: viewerID, accepted: false
        )
        XCTAssertFalse(
            ATHLTHArenaResultHistoryPresentation.needsYourVote(
                result: pending,
                viewerID: viewerID,
                eligibleIDs: [viewerID],
                votes: [rejectedVote]
            )
        )
    }

    func testDeterministicOrderForEqualTimestamps() {
        let roundID = UUID()
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let first = result(roundID: roundID, status: "pending", age: 5, id: firstID)
        let second = result(roundID: roundID, status: "approved", age: 5, id: secondID)
        XCTAssertEqual(
            ATHLTHArenaResultHistoryPresentation.recent(
                [second, first], for: [roundID]
            ).map(\.id),
            [firstID, secondID]
        )
    }
}
