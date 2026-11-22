import XCTest
@testable import ATHLTH

final class ATHLTHTournamentSeasonContinuationTests: XCTestCase {
    private let owner = UUID()
    private let rival = UUID()

    func testLeagueGroupLeagueAndCupCanContinueOnlyAfterCompletion() {
        for format in ATHLTHTournamentFormat.allCases {
            XCTAssertTrue(ATHLTHTournamentSeasonContinuation.canContinue(
                format: format, status: "completed",
                ownerID: owner, currentUserID: owner
            ))
            XCTAssertFalse(ATHLTHTournamentSeasonContinuation.canContinue(
                format: format, status: "active",
                ownerID: owner, currentUserID: owner
            ))
            XCTAssertFalse(ATHLTHTournamentSeasonContinuation.canContinue(
                format: format, status: "inviting",
                ownerID: owner, currentUserID: owner
            ))
            XCTAssertFalse(ATHLTHTournamentSeasonContinuation.canContinue(
                format: format, status: "cancelled",
                ownerID: owner, currentUserID: owner
            ))
            XCTAssertFalse(ATHLTHTournamentSeasonContinuation.canContinue(
                format: format, status: "completed",
                ownerID: owner, currentUserID: rival
            ))
        }
        XCTAssertEqual(ATHLTHCompetitionFormat.allCases,
                       [.duel, .league, .cup])
        // Duel is a Challenge, not an ATHLTHTournamentFormat: no seasons.
        XCTAssertEqual(Set(ATHLTHTournamentFormat.allCases),
                       Set([.league, .groups, .cup]))
    }

    func testNextSeasonTitleIncrementsWithoutDuplicatingSuffixes() {
        let policy = ATHLTHTournamentSeasonContinuation.self
        XCTAssertEqual(policy.nextTitle(from: "Morgencup"), "Morgencup · Sesong 2")
        XCTAssertEqual(policy.nextTitle(from: "Høstliga · Sesong 2"),
                       "Høstliga · Sesong 3")
        XCTAssertEqual(policy.nextTitle(from: "Klubbliga - sesong 3"),
                       "Klubbliga · Sesong 4")
        XCTAssertLessThanOrEqual(
            policy.nextTitle(from: String(repeating: "L", count: 80)).count, 80
        )
    }

    private func tournament(format: ATHLTHTournamentFormat,
                            status: String) -> ATHLTHTournamentRemote {
        ATHLTHTournamentRemote(
            id: UUID(), ownerID: owner,
            clubID: nil, seasonID: nil,
            title: "Testliga", format: format,
            groupSize: 4, qualifiersPerGroup: 2,
            winPoints: 4, drawPoints: 1,
            status: status,
            exerciseMode: .vote,
            exerciseCount: 6,
            proposalsCloseAt: nil, votesCloseAt: nil,
            approvePlayerChanges: true,
            exerciseSelectionFinalizedAt: nil,
            allowedActivities: [.running, .walking],
            rulesAuthority: .group,
            cadenceDays: 7, completionHours: 48,
            rulesConfirmedAt: nil,
            rotationMode: .sequence,
            restWeekdays: [1, 7],
            proofMode: .verified,
            publicResults: false,
            allowExtensions: false,
            ruleVersion: 2, rulesFrozenAt: nil,
            createdAt: Date(), startedAt: Date(),
            completedAt: status == "completed" ? Date() : nil
        )
    }

    private func entry(_ athlete: UUID, response: String,
                       seed: Int) -> ATHLTHTournamentRemoteEntry {
        ATHLTHTournamentRemoteEntry(
            tournamentID: UUID(), userID: athlete, seed: seed,
            response: response, respondedAt: nil,
            groupIndex: nil, isReady: false, readyAt: nil,
            removedAt: nil, replacedBy: nil,
            agreedRuleVersion: nil, agreedRulesAt: nil
        )
    }

    func testFinishedLeagueCreatesFreshRulesAndReinvitesWithoutOldResults() throws {
        let ended = tournament(format: .groups, status: "completed")
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let rejected = UUID()
        let participants = [
            entry(owner, response: "accepted", seed: 1),
            entry(rival, response: "accepted", seed: 2),
            entry(rejected, response: "declined", seed: 3)
        ]
        let next = try XCTUnwrap(ATHLTHTournamentSeasonContinuation.nextDraft(
            from: ended, entries: participants,
            athleteNames: [owner: "Arrangør", rival: "Utfordrer"],
            currentUserID: owner, now: now
        ))
        XCTAssertNotEqual(next.id, ended.id)
        XCTAssertNil(next.seasonID)
        XCTAssertEqual(next.title, "Testliga · Sesong 2")
        XCTAssertEqual(next.format, .groups)
        XCTAssertEqual(next.participants.map(\.id), [owner, rival])
        XCTAssertEqual(next.rulesAuthority, .group)
        XCTAssertEqual(next.allowedActivities, [.running, .walking])
        XCTAssertEqual(next.exerciseMode, .vote)
        XCTAssertEqual(next.exerciseCount, 6)
        XCTAssertEqual(next.rotationMode, .sequence)
        XCTAssertEqual(next.winPoints, 4)
        XCTAssertEqual(next.drawPoints, 1)
        XCTAssertEqual(next.cadenceDays, 7)
        XCTAssertEqual(next.proposalsCloseAt,
                       now.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(next.votesCloseAt,
                       now.addingTimeInterval(3 * 86_400))
        XCTAssertTrue(next.warmupRounds.isEmpty)
        // The old record remains immutable: no new ID reuses its match graph.
        XCTAssertEqual(ended.title, "Testliga")
        XCTAssertEqual(ended.status, "completed")
    }

    func testActiveTournamentCannotRenewAndOwnerMustRemainEligible() {
        let entries = [
            entry(owner, response: "accepted", seed: 1),
            entry(rival, response: "accepted", seed: 2)
        ]
        XCTAssertNil(ATHLTHTournamentSeasonContinuation.nextDraft(
            from: tournament(format: .cup, status: "active"),
            entries: entries, athleteNames: [:], currentUserID: owner
        ))
        XCTAssertNil(ATHLTHTournamentSeasonContinuation.nextDraft(
            from: tournament(format: .league, status: "completed"),
            entries: entries, athleteNames: [:], currentUserID: rival
        ))
        XCTAssertNil(ATHLTHTournamentSeasonContinuation.nextDraft(
            from: tournament(format: .league, status: "completed"),
            entries: [entry(rival, response: "accepted", seed: 1)],
            athleteNames: [:], currentUserID: owner
        ))
    }
}
