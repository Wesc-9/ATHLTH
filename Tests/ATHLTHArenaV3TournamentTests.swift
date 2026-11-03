import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHArenaV3TournamentTests: XCTestCase {
    private func athletes(_ names: [String]) -> [ATHLTHTournamentParticipant] {
        names.map { ATHLTHTournamentParticipant(id: UUID(), username: $0) }
    }

    func testGroupSizeFourProducesBalancedGroups() {
        let roster = athletes((1...10).map { "athlete\($0)" })
        let groups = ATHLTHTournamentStructure.groups(roster, size: 4)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.map(\.count), [4, 3, 3])
        XCTAssertEqual(Set(groups.flatMap { $0.map(\.id) }).count, 10)
    }

    func testSingleLeagueHasRoundRobinMatchCount() {
        XCTAssertEqual(ATHLTHTournamentStructure.leagueMatchCount(4), 6)
        XCTAssertEqual(ATHLTHTournamentStructure.leagueMatchCount(10), 45)
        XCTAssertEqual(ATHLTHTournamentStructure.leagueMatchCount(1), 0)
    }

    func testCupUsesByesWithoutInventingResults() {
        let roster = athletes(["A", "B", "C", "D", "E", "F"])
        XCTAssertEqual(ATHLTHTournamentStructure.bracketSize(roster.count), 8)
        let first = ATHLTHTournamentStructure.firstCupRound(roster)
        XCTAssertEqual(first.count, 4)
        XCTAssertEqual(first.filter { $0.0 == "Frirunde" || $0.1 == "Frirunde" }.count, 2)
    }

    func testMultipleCupDraftsRemainSeparate() throws {
        let owner = UUID()
        let first = ATHLTHTournamentDraft(ownerID: owner, clubID: nil,
            title: "Cup 1", format: .cup, groupSize: 4,
            qualifiersPerGroup: 2, participants: athletes(["A", "B"]))
        let second = ATHLTHTournamentDraft(ownerID: owner, clubID: UUID(),
            title: "Klubbens cup", format: .cup, groupSize: 4,
            qualifiersPerGroup: 2, participants: athletes(["C", "D", "E"]))
        let decoded = try JSONDecoder().decode(
            [ATHLTHTournamentDraft].self,
            from: JSONEncoder().encode([first, second]))
        XCTAssertEqual(decoded.count, 2)
        XCTAssertNotEqual(decoded[0].id, decoded[1].id)
        XCTAssertNil(decoded[0].clubID)
        XCTAssertNotNil(decoded[1].clubID)
    }

    func testTreadmillCorrectionBoundsInclusive() {
        let measured = 2000.0
        XCTAssertTrue(ATHLTHChallengeTreadmillReviewPolicy.withinMargin(
            measured: measured, submitted: 1700))
        XCTAssertTrue(ATHLTHChallengeTreadmillReviewPolicy.withinMargin(
            measured: measured, submitted: 2300))
        XCTAssertFalse(ATHLTHChallengeTreadmillReviewPolicy.withinMargin(
            measured: measured, submitted: 1699))
        XCTAssertFalse(ATHLTHChallengeTreadmillReviewPolicy.withinMargin(
            measured: measured, submitted: 2301))
        XCTAssertFalse(ATHLTHChallengeTreadmillReviewPolicy.withinMargin(
            measured: measured, submitted: .infinity))
    }
}
