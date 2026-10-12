import Foundation
import XCTest
@testable import ATHLTH

/// Rendering-only tests: no device action or Live Ghost result grants
/// Arena points. The server's persisted round-point row is authoritative.
final class ATHLTHArenaApprovedRoundPointsTests: XCTestCase {
    private let round = UUID()
    private let series = UUID()
    private let athleteSlot = UUID()

    private func proposal(status: String) -> ATHLTHArenaRoundResult {
        ATHLTHArenaRoundResult(
            id: UUID(),
            seriesID: series,
            roundID: round,
            proposedBy: UUID(),
            rankedSlots: [athleteSlot],
            evidenceNote: "Participant-reported result",
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func points(
        _ score: Double,
        roundID: UUID? = nil,
        slotID: UUID? = nil
    ) -> ATHLTHArenaRoundPoints {
        ATHLTHArenaRoundPoints(
            roundID: roundID ?? round,
            slotID: slotID ?? athleteSlot,
            points: score
        )
    }

    func testApprovedResultDisplaysOnlyPersistedPoints() {
        XCTAssertEqual(
            ATHLTHArenaResultHistoryPresentation.awardedPoints(
                for: proposal(status: "approved"),
                slotID: athleteSlot,
                recorded: [points(3)]
            ),
            3
        )
    }

    func testPendingAndRejectedProposalsNeverGrantPoints() {
        for status in ["pending", "rejected", "expired", "unknown"] {
            XCTAssertNil(
                ATHLTHArenaResultHistoryPresentation.awardedPoints(
                    for: proposal(status: status),
                    slotID: athleteSlot,
                    recorded: [points(3)]
                )
            )
        }
    }

    func testPointsFromAnotherRoundOrAthleteAreNotSubstituted() {
        XCTAssertNil(
            ATHLTHArenaResultHistoryPresentation.awardedPoints(
                for: proposal(status: "approved"),
                slotID: athleteSlot,
                recorded: [points(5, roundID: UUID()),
                           points(8, slotID: UUID())]
            )
        )
    }

    func testNoPointsRecordIsNotAutomaticallyZero() {
        XCTAssertNil(
            ATHLTHArenaResultHistoryPresentation.awardedPoints(
                for: proposal(status: "approved"),
                slotID: athleteSlot,
                recorded: []
            )
        )
        XCTAssertNil(
            ATHLTHArenaResultHistoryPresentation.awardedPoints(
                for: proposal(status: "approved"),
                slotID: nil,
                recorded: [points(3)]
            )
        )
    }

    func testRealZeroPointAwardCanBeDisplayed() {
        XCTAssertEqual(
            ATHLTHArenaResultHistoryPresentation.awardedPoints(
                for: proposal(status: "approved"),
                slotID: athleteSlot,
                recorded: [points(0)]
            ),
            0
        )
    }

    func testDuplicateRecordsMustNotInflateOrInventAnAward() {
        XCTAssertNil(
            ATHLTHArenaResultHistoryPresentation.awardedPoints(
                for: proposal(status: "approved"),
                slotID: athleteSlot,
                recorded: [points(2), points(2)]
            )
        )
    }

    func testNonfiniteOrNegativeLegacyPointsAreHidden() {
        for invalid in [Double.nan, Double.infinity, -3] {
            XCTAssertNil(
                ATHLTHArenaResultHistoryPresentation.awardedPoints(
                    for: proposal(status: "approved"),
                    slotID: athleteSlot,
                    recorded: [points(invalid)]
                )
            )
        }
    }
}
