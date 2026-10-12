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
