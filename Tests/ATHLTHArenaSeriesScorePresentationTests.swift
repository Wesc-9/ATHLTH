import Foundation
import XCTest
@testable import ATHLTH

/// Arena phase 4: the client displays only points already settled by
/// the server. These tests never allocate scores or approve a result.
final class ATHLTHArenaSeriesScorePresentationTests: XCTestCase {
    private let seriesID = UUID()
    private let created = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(
        _ points: Double,
        response: String = "accepted",
        order: TimeInterval = 0,
        userID: UUID? = UUID()
    ) -> ATHLTHArenaRemoteMember {
        ATHLTHArenaRemoteMember(
            slotID: UUID(),
            seriesID: seriesID,
            userID: userID,
            response: response,
            points: points,
            createdAt: created.addingTimeInterval(order)
        )
    }

    func testApprovedTiesSharePlaceAndSkipNextRank() {
        let a = entry(3, order: 1)
        let b = entry(5, order: 2)
        let c = entry(5, order: 3)
        let table = ATHLTHArenaSeriesScorePresentation.ordered([a, c, b])
        XCTAssertEqual(
            ATHLTHArenaSeriesScorePresentation.competitionRank(
                for: b, among: table
            ), 1
        )
        XCTAssertEqual(
            ATHLTHArenaSeriesScorePresentation.competitionRank(
                for: c, among: table
            ), 1
        )
        XCTAssertEqual(
            ATHLTHArenaSeriesScorePresentation.competitionRank(
                for: a, among: table
            ), 3
        )
    }

    func testZeroAndInvalidPointsAreUnrankedAndNotChampions() {
        let a = entry(0)
        let b = entry(.nan)
        let c = entry(-10)
        let table = ATHLTHArenaSeriesScorePresentation.ordered([b, a, c])
        for row in table {
            XCTAssertNil(
                ATHLTHArenaSeriesScorePresentation.competitionRank(
                    for: row, among: table
                )
            )
        }
        XCTAssertEqual(
            ATHLTHArenaSeriesScorePresentation.approvedLeaderPoints(
                among: table
            ), 0
        )
        XCTAssertEqual(
            ATHLTHArenaSeriesScorePresentation.visiblePoints(.infinity), 0
        )
    }

    func testGapReflectsOnlyAwardedMemberPoints() {
        let first = entry(8)
        let second = entry(5)
        let table = ATHLTHArenaSeriesScorePresentation.ordered([first, second])
        XCTAssertEqual(
            ATHLTHArenaSeriesScorePresentation.gapToLeader(
                for: second, among: table
            ), 3, accuracy: 0.001
        )
        XCTAssertEqual(
            ATHLTHArenaSeriesScorePresentation.gapToLeader(
                for: first, among: table
            ), 0
        )
    }

    func testInvitedUsersNeverAppearInApprovedStandings() {
        let accepted = entry(3)
        let invited = entry(10, response: "invited")
        let deleted = entry(1, response: "deleted", userID: nil)
        let table = ATHLTHArenaSeriesScorePresentation.ordered(
            [invited, deleted, accepted]
        )
        XCTAssertEqual(table.count, 2)
        XCTAssertFalse(table.contains(where: { $0.slotID == invited.slotID }))
        XCTAssertEqual(table.first?.slotID, accepted.slotID)
    }

    func testStableTieOrderingUsesRecordedEntryDate() {
        let early = entry(4, order: 1)
        let later = entry(4, order: 2)
        let table = ATHLTHArenaSeriesScorePresentation.ordered([later, early])
        XCTAssertEqual(table.map(\.slotID), [early.slotID, later.slotID])
    }

    func testFractionalServerPointsSortPredictablyNearTieThreshold() {
        let lower = entry(5.0004, order: 0)
        let upper = entry(5.0009, order: 10)
        let table = ATHLTHArenaSeriesScorePresentation.ordered(
            [lower, upper]
        )
        XCTAssertEqual(table.map(\.slotID), [upper.slotID, lower.slotID])
        // Results this close share the displayed competition position,
        // but the sort itself must still have a strict stable order.
        XCTAssertEqual(
            ATHLTHArenaSeriesScorePresentation.competitionRank(
                for: lower, among: table
            ), 1
        )
    }

    func testUnlistedAthleteCannotAcquireACompetitiveRank() {
        let shown = entry(6)
        let outsider = entry(10)
        XCTAssertNil(
            ATHLTHArenaSeriesScorePresentation.competitionRank(
                for: outsider,
                among: [shown]
            )
        )
        XCTAssertEqual(
            ATHLTHArenaSeriesScorePresentation.gapToLeader(
                for: outsider,
                among: [shown]
            ), 0
        )
    }
    func testChampionRequiresEveryRoundToBeApproved() {
        XCTAssertTrue(ATHLTHArenaSeriesScorePresentation.mayDeclareChampion(
            seriesStatus: "completed",
            completionReason: nil,
            resultsLoaded: true,
            progress: ATHLTHArenaRoundProgress(total: 3, approved: 3, pending: 0),
            leaderPoints: 9
        ))
        XCTAssertFalse(ATHLTHArenaSeriesScorePresentation.mayDeclareChampion(
            seriesStatus: "completed",
            completionReason: nil,
            resultsLoaded: true,
            progress: ATHLTHArenaRoundProgress(total: 3, approved: 2, pending: 1),
            leaderPoints: 9
        ))
    }

    func testChampionCannotBeDeclaredForUnresolvedOrMissingRounds() {
        for progress in [
            ATHLTHArenaRoundProgress(total: 0, approved: 0, pending: 0),
            ATHLTHArenaRoundProgress(total: 3, approved: 2, pending: 0),
            ATHLTHArenaRoundProgress(total: 3, approved: 0, pending: 3)
        ] {
            XCTAssertFalse(ATHLTHArenaSeriesScorePresentation.mayDeclareChampion(
                seriesStatus: "completed",
                completionReason: nil,
                resultsLoaded: true,
                progress: progress,
                leaderPoints: 9
            ))
        }
    }

    func testChampionRequiresCurrentAuthoritativeResults() {
        let settled = ATHLTHArenaRoundProgress(
            total: 2, approved: 2, pending: 0
        )
        XCTAssertFalse(ATHLTHArenaSeriesScorePresentation.mayDeclareChampion(
            seriesStatus: "completed",
            completionReason: nil,
            resultsLoaded: false,
            progress: settled,
            leaderPoints: 6
        ))
        XCTAssertFalse(ATHLTHArenaSeriesScorePresentation.mayDeclareChampion(
            seriesStatus: "active",
            completionReason: nil,
            resultsLoaded: true,
            progress: settled,
            leaderPoints: 6
        ))
        XCTAssertFalse(ATHLTHArenaSeriesScorePresentation.mayDeclareChampion(
            seriesStatus: "completed",
            completionReason: "deadline_unresolved",
            resultsLoaded: true,
            progress: settled,
            leaderPoints: 6
        ))
    }

    func testChampionNeverFromEmptyOrInvalidLeaderPoints() {
        let settled = ATHLTHArenaRoundProgress(
            total: 1, approved: 1, pending: 0
        )
        for points: Double in [0, -3, .nan, .infinity] {
            XCTAssertFalse(ATHLTHArenaSeriesScorePresentation.mayDeclareChampion(
                seriesStatus: "completed",
                completionReason: nil,
                resultsLoaded: true,
                progress: settled,
                leaderPoints: points
            ))
        }
    }

}
