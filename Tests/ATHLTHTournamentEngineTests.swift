import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTournamentEngineTests: XCTestCase {
    private func roster(_ count: Int) -> [ATHLTHTournamentParticipant] {
        (1...count).map {
            ATHLTHTournamentParticipant(id: UUID(), username: "utover\($0)")
        }
    }

    private func draft(
        format: ATHLTHTournamentFormat = .league,
        count: Int = 8, groupSize: Int = 4,
        warmupCount: Int = 0
    ) -> ATHLTHTournamentDraft {
        let athleteList = roster(count)
        return ATHLTHTournamentDraft(
            ownerID: athleteList[0].id,
            clubID: nil, title: "Testturnering",
            format: format, groupSize: groupSize,
            qualifiersPerGroup: 2, participants: athleteList,
            warmupRounds: (0..<warmupCount).map {
                ATHLTHTournamentWarmupRound(title: "Oppvarming \($0 + 1)")
            }
        )
    }

    func testWarmupNeverChangesPointsOrAdvancement() throws {
        let tournament = draft(format: .cup, count: 4, warmupCount: 2)
        let all = try ATHLTHTournamentEngine.initialFixtures(for: tournament)
        let practice = all.filter { $0.phase == .warmup }
        XCTAssertFalse(practice.isEmpty)
        XCTAssertTrue(practice.allSatisfy { !$0.phase.awardsPoints && !$0.phase.eliminates })
        let first = try XCTUnwrap(practice.first)
        let other = try XCTUnwrap(first.awayID)
        let result = try XCTUnwrap(ATHLTHTournamentApprovedResult(
            homeScore: 9, awayScore: 1,
            proposedBy: first.homeID, approvedBy: other
        ))
        let scoredPractice = try ATHLTHTournamentEngine.approve(first, result: result)
        XCTAssertNil(scoredPractice.approvedWinnerID)
        XCTAssertTrue(ATHLTHTournamentEngine.standings(
            for: tournament.participants, fixtures: [scoredPractice]
        ).allSatisfy { $0.points == 0 && $0.played == 0 })
    }

    func testRoundRobinSchedulesEveryPairExactlyOnce() throws {
        for number in [3, 4, 7, 8] {
            let tournament = draft(count: number)
            let fixtures = try ATHLTHTournamentEngine.initialFixtures(for: tournament)
            XCTAssertEqual(fixtures.count, number * (number - 1) / 2)
            let pairs = Set(fixtures.map { match in
                [match.homeID.uuidString, match.awayID!.uuidString]
                    .sorted().joined(separator: ":")
            })
            XCTAssertEqual(pairs.count, fixtures.count)
        }
    }

    func testGroupedLeagueQualifiesOnlyAfterConfirmedMatches() throws {
        let tournament = draft(format: .groups, count: 8, groupSize: 4)
        let all = try ATHLTHTournamentEngine.initialFixtures(for: tournament)
        XCTAssertEqual(all.filter { $0.phase == .group }.count, 12)
        XCTAssertThrowsError(
            try ATHLTHTournamentEngine.qualifiedForPlayoff(
                draft: tournament, fixtures: all
            )
        ) { XCTAssertEqual($0 as? ATHLTHTournamentEngineError, .roundNotComplete) }
        let approved = try all.map { match -> ATHLTHTournamentFixture in
            let other = try XCTUnwrap(match.awayID)
            let result = try XCTUnwrap(ATHLTHTournamentApprovedResult(
                homeScore: 2, awayScore: 1,
                proposedBy: match.homeID, approvedBy: other
            ))
            return try ATHLTHTournamentEngine.approve(match, result: result)
        }
        let qualifierIDs = try ATHLTHTournamentEngine.qualifiedForPlayoff(
            draft: tournament, fixtures: approved
        )
        XCTAssertEqual(qualifierIDs.count, 4)
        XCTAssertEqual(Set(qualifierIDs).count, 4)
    }

    func testKnockoutRequiresOpponentApproval() throws {
        let tournament = draft(format: .cup, count: 4)
        let fixtures = try ATHLTHTournamentEngine.initialFixtures(for: tournament)
        XCTAssertEqual(fixtures.count, 2)
        XCTAssertThrowsError(try ATHLTHTournamentEngine.nextKnockoutRound(
            after: fixtures, phase: .cup
        )) { XCTAssertEqual($0 as? ATHLTHTournamentEngineError, .roundNotComplete) }
        let result = ATHLTHTournamentApprovedResult(
            homeScore: 1, awayScore: 0,
            proposedBy: fixtures[0].homeID, approvedBy: fixtures[0].homeID
        )
        XCTAssertNil(result)
        let done = try fixtures.map { match -> ATHLTHTournamentFixture in
            let other = try XCTUnwrap(match.awayID)
            return try ATHLTHTournamentEngine.approve(
                match,
                result: XCTUnwrap(ATHLTHTournamentApprovedResult(
                    homeScore: 1, awayScore: 0,
                    proposedBy: match.homeID, approvedBy: other
                ))
            )
        }
        let final = try ATHLTHTournamentEngine.nextKnockoutRound(
            after: done, phase: .cup
        )
        XCTAssertEqual(final.count, 1)
        XCTAssertEqual(final[0].round, 2)
        XCTAssertEqual(final[0].homeID, done[0].homeID)
        XCTAssertEqual(final[0].awayID, done[1].homeID)
    }

    func testFiveAthleteCupAssignsThreeRealByes() throws {
        let tour = draft(format: .cup, count: 5)
        let fixtures = try ATHLTHTournamentEngine.initialFixtures(for: tour)
        XCTAssertEqual(fixtures.count, 4)
        XCTAssertEqual(fixtures.filter(\.isBye).count, 3)
        XCTAssertEqual(Set(fixtures.map(\.homeID)).count, 4)
    }

    func testTiebreakersUsePointsThenDifferenceThenScored() throws {
        let athletes = roster(3)
        var matches = ATHLTHTournamentEngine.roundRobin(
            athletes.map(\.id), phase: .league
        )
        XCTAssertEqual(matches.count, 3)
        for i in matches.indices {
            let other = try XCTUnwrap(matches[i].awayID)
            let approved = try XCTUnwrap(ATHLTHTournamentApprovedResult(
                homeScore: i == 0 ? 4 : 1,
                awayScore: i == 0 ? 2 : 1,
                proposedBy: matches[i].homeID, approvedBy: other
            ))
            matches[i] = try ATHLTHTournamentEngine.approve(
                matches[i], result: approved
            )
        }
        let table = ATHLTHTournamentEngine.standings(
            for: athletes, fixtures: matches
        )
        XCTAssertEqual(table.reduce(0) { $0 + $1.played }, 6)
        XCTAssertEqual(table.reduce(0) { $0 + $1.points }, 5)
    }

    func testDuplicateParticipantIsRejected() throws {
        var participants = roster(3)
        participants.append(participants[0])
        XCTAssertThrowsError(try ATHLTHTournamentEngine.validate(participants)) {
            XCTAssertEqual($0 as? ATHLTHTournamentEngineError, .duplicateParticipant)
        }
    }

    func testNoDrawMayAdvanceInCup() throws {
        let players = roster(2)
        let fixture = ATHLTHTournamentFixture(
            phase: .cup, round: 1,
            homeID: players[0].id, awayID: players[1].id
        )
        let result = try XCTUnwrap(ATHLTHTournamentApprovedResult(
            homeScore: 10, awayScore: 10,
            proposedBy: players[0].id, approvedBy: players[1].id
        ))
        XCTAssertThrowsError(
            try ATHLTHTournamentEngine.approve(fixture, result: result)
        ) { XCTAssertEqual($0 as? ATHLTHTournamentEngineError, .drawNotPermitted) }
    }
}
