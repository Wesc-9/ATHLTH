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

    func testNeedsMyVoteFilterExcludesOtherVotesAndOtherStatuses() {
        let viewer = UUID()
        let round = UUID()
        let pending = result(roundID: round, status: "pending", age: 4)
        let alreadyVoted = result(roundID: round, status: "pending", age: 3)
        let approved = result(roundID: round, status: "approved", age: 2)
        let rejected = result(roundID: round, status: "rejected", age: 1)
        let vote = ATHLTHArenaRoundResultVote(
            resultID: alreadyVoted.id, userID: viewer, accepted: false
        )
        let filtered = ATHLTHArenaResultHistoryPresentation.filtered(
            [approved, alreadyVoted, pending, rejected],
            filter: .requiresMyVote,
            viewerID: viewer,
            eligibleIDs: [viewer],
            votes: [vote]
        )
        XCTAssertEqual(filtered.map(\.id), [pending.id])
    }

    func testOutsiderNeverGetsPersonalVotingReminder() {
        let pending = result(
            roundID: UUID(), status: "pending", age: 1
        )
        XCTAssertTrue(
            ATHLTHArenaResultHistoryPresentation.filtered(
                [pending],
                filter: .requiresMyVote,
                viewerID: UUID(),
                eligibleIDs: [UUID()],
                votes: []
            ).isEmpty
        )
    }

    func testApprovedFilterDoesNotInferApprovalFromVotes() {
        let viewer = UUID()
        let pending = result(roundID: UUID(), status: "pending", age: 3)
        let approved = result(roundID: UUID(), status: "approved", age: 1)
        let vote = ATHLTHArenaRoundResultVote(
            resultID: pending.id, userID: viewer, accepted: true
        )
        let filtered = ATHLTHArenaResultHistoryPresentation.filtered(
            [pending, approved],
            filter: .approved,
            viewerID: viewer,
            eligibleIDs: [viewer],
            votes: [vote]
        )
        XCTAssertEqual(filtered.map(\.id), [approved.id])
    }

    func testAllFilterPreservesHistoricalRejectedProposals() {
        let a = result(roundID: UUID(), status: "rejected", age: 3)
        let b = result(roundID: UUID(), status: "expired", age: 2)
        let filtered = ATHLTHArenaResultHistoryPresentation.filtered(
            [a, b],
            filter: .all,
            viewerID: UUID(),
            eligibleIDs: [],
            votes: []
        )
        XCTAssertEqual(filtered.map(\.id), [a.id, b.id])
    }

    func testFilteredHistoryCanBeLimitedWithoutLosingVoteActions() {
        let viewer = UUID(), round = UUID()
        let waiting = (0..<8).map {
            result(roundID: round, status: "pending", age: Double($0))
        }
        let matching = ATHLTHArenaResultHistoryPresentation.filtered(
            waiting,
            filter: .requiresMyVote,
            viewerID: viewer,
            eligibleIDs: [viewer],
            votes: []
        )
        XCTAssertEqual(matching.count, 8)
        XCTAssertEqual(
            ATHLTHArenaResultHistoryPresentation.recent(
                matching, for: [round]
            ).count,
            4
        )
    }

    func testNextVotePrioritizesOldestEligiblePendingProposal() {
        let viewer = UUID(), roundID = UUID()
        let first = result(roundID: roundID, status: "pending", age: 50)
        let newer = result(roundID: roundID, status: "pending", age: 1)
        let approved = result(roundID: roundID, status: "approved", age: 150)
        let fromOtherSeries = result(
            roundID: UUID(), status: "pending", age: 500
        )
        XCTAssertEqual(
            ATHLTHArenaResultHistoryPresentation.nextVote(
                results: [newer, approved, fromOtherSeries, first],
                roundIDs: [roundID],
                viewerID: viewer,
                eligibleIDs: [viewer],
                votes: []
            )?.id,
            first.id
        )
    }

    func testNextVoteSkipsAlreadyVotedAndRejectsOutsiders() {
        let viewer = UUID(), roundID = UUID()
        let previous = result(roundID: roundID, status: "pending", age: 40)
        let current = result(roundID: roundID, status: "pending", age: 10)
        let myVote = ATHLTHArenaRoundResultVote(
            resultID: previous.id, userID: viewer, accepted: true
        )
        XCTAssertEqual(
            ATHLTHArenaResultHistoryPresentation.nextVote(
                results: [previous, current],
                roundIDs: [roundID],
                viewerID: viewer,
                eligibleIDs: [viewer],
                votes: [myVote]
            )?.id,
            current.id
        )
        XCTAssertNil(
            ATHLTHArenaResultHistoryPresentation.nextVote(
                results: [current],
                roundIDs: [roundID],
                viewerID: UUID(),
                eligibleIDs: [viewer],
                votes: []
            )
        )
    }

    func testNextVoteDoesNotTreatExpiredOrSettledAsActionable() {
        let viewer = UUID(), roundID = UUID()
        let statuses = ["expired", "approved", "rejected", "cancelled"]
        let history = statuses.map {
            result(roundID: roundID, status: $0, age: 20)
        }
        XCTAssertNil(
            ATHLTHArenaResultHistoryPresentation.nextVote(
                results: history,
                roundIDs: [roundID],
                viewerID: viewer,
                eligibleIDs: [viewer],
                votes: []
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
    func testVoteControlsRequireFreshAcceptedActiveSeries() {
        let roundID = UUID()
        let viewer = UUID()
        let proposal = result(roundID: roundID, status: "pending", age: 2)
        let eligible: Set<UUID> = [viewer, UUID()]
        XCTAssertTrue(ATHLTHArenaResultHistoryPresentation.canReviewVote(
            result: proposal,
            seriesStatus: "active",
            resultsLoaded: true,
            viewerID: viewer,
            eligibleIDs: eligible,
            votes: []
        ))
        XCTAssertFalse(ATHLTHArenaResultHistoryPresentation.canReviewVote(
            result: proposal,
            seriesStatus: "active",
            resultsLoaded: false,
            viewerID: viewer,
            eligibleIDs: eligible,
            votes: []
        ))
    }

    func testCompletedOrDraftCompetitionCannotOfferStaleVote() {
        let viewer = UUID()
        let proposal = result(roundID: UUID(), status: "pending", age: 10)
        for state in ["completed", "draft", "cancelled"] {
            XCTAssertFalse(ATHLTHArenaResultHistoryPresentation.canReviewVote(
                result: proposal,
                seriesStatus: state,
                resultsLoaded: true,
                viewerID: viewer,
                eligibleIDs: [viewer],
                votes: []
            ))
        }
    }

    func testHistoricalApprovedOrExpiredProposalsCannotBeVotedAgain() {
        let viewer = UUID()
        for state in ["approved", "rejected", "expired", "unknown"] {
            let proposal = result(roundID: UUID(), status: state, age: 20)
            XCTAssertFalse(ATHLTHArenaResultHistoryPresentation.canReviewVote(
                result: proposal,
                seriesStatus: "active",
                resultsLoaded: true,
                viewerID: viewer,
                eligibleIDs: [viewer],
                votes: []
            ))
        }
    }

    func testAlreadyVotedOrIneligibleAthleteCannotReviewVote() {
        let viewer = UUID()
        let proposal = result(roundID: UUID(), status: "pending", age: 10)
        XCTAssertFalse(ATHLTHArenaResultHistoryPresentation.canReviewVote(
            result: proposal,
            seriesStatus: "active",
            resultsLoaded: true,
            viewerID: viewer,
            eligibleIDs: [UUID()],
            votes: []
        ))
        XCTAssertFalse(ATHLTHArenaResultHistoryPresentation.canReviewVote(
            result: proposal,
            seriesStatus: "active",
            resultsLoaded: true,
            viewerID: viewer,
            eligibleIDs: [viewer],
            votes: [.init(resultID: proposal.id, userID: viewer, accepted: false)]
        ))
    }

}
