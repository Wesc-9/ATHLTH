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
                       [.duel, .single, .league, .cup])
        // A duel is a shared event and is renewed through rematch, not seasons.
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
                            status: String,
                            id: UUID = UUID(),
                            rules: ATHLTHCompetitionRaceRules = ATHLTHCompetitionRaceRules(),
                            singleEvent: Bool = false) -> ATHLTHTournamentRemote {
        ATHLTHTournamentRemote(
            id: id, ownerID: owner,
            clubID: nil, seasonID: nil,
            title: "Testliga", format: format,
            groupSize: 4, qualifiersPerGroup: 2,
            winPoints: 4, drawPoints: 1,
            status: status,
            singleEventMode: singleEvent,
            raceSignalAt: nil,
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
            completedAt: status == "completed" ? Date() : nil,
            plannedStartsAt: nil,
            startMode: "manual",
            raceRules: rules,
            requiredEnvironment: "any",
            meetingPlace: nil,
            meetingLat: nil,
            meetingLon: nil,
            simpleMode: false,
            invitationDays: 3,
            unansweredPolicy: "cancel",
            replacementUntil: nil,
            allowFeedPost: true,
            feedPublishedAt: nil,
            releaseMode: "interval",
            releaseEvery: 7,
            releaseUnit: "day",
            invitationPermission: "admin",
            joinApproval: "admin",
            allowedActions: "",
            prohibitedActions: "",
            prizeFirst: "",
            prizeSecond: "",
            prizeThird: "",
            loserConsequence: ""
        )
    }

    private func entry(_ athlete: UUID, response: String,
                       seed: Int) -> ATHLTHTournamentRemoteEntry {
        ATHLTHTournamentRemoteEntry(
            tournamentID: UUID(), userID: athlete, seed: seed,
            response: response, respondedAt: nil,
            expiresAt: nil, groupIndex: nil, isReady: false, readyAt: nil,
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
        XCTAssertEqual(next.competitionSettings.race.previousCompetitionID, ended.id)
        XCTAssertEqual(next.competitionSettings.race.seasonNumber, 2)
        XCTAssertNil(next.competitionSettings.startsAt)
        XCTAssertNil(next.competitionSettings.endsAt)
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

    func testHistoryFollowsBothDirectionsButNeverMatchesUnrelatedTitles() {
        let first = tournament(format: .league, status: "completed")
        var secondRules = ATHLTHCompetitionRaceRules()
        secondRules.previousCompetitionID = first.id
        secondRules.seasonNumber = 2
        let second = tournament(format: .league, status: "completed", rules: secondRules)
        var thirdRules = ATHLTHCompetitionRaceRules()
        thirdRules.previousCompetitionID = second.id
        thirdRules.seasonNumber = 3
        let third = tournament(format: .league, status: "active", rules: thirdRules)
        let unrelated = tournament(format: .league, status: "completed")
        let otherFormat = tournament(format: .cup, status: "active", rules: thirdRules)
        let single = tournament(format: .league, status: "active", rules: thirdRules, singleEvent: true)
        let visible = [unrelated, third, first, second, otherFormat, single, second]
        for current in [first, second, third] {
            XCTAssertEqual(
                ATHLTHTournamentSeasonContinuation.history(current: current, visible: visible).map(\.id),
                [third.id, second.id, first.id]
            )
        }
        XCTAssertTrue(ATHLTHTournamentSeasonContinuation.history(current: single, visible: visible).isEmpty)
    }

    func testHistoryDoesNotBridgeInvisibleAncestorAndTerminatesCycles() {
        let firstID = UUID()
        let secondID = UUID()
        var firstRules = ATHLTHCompetitionRaceRules()
        firstRules.previousCompetitionID = secondID
        firstRules.seasonNumber = 1
        var secondRules = ATHLTHCompetitionRaceRules()
        secondRules.previousCompetitionID = firstID
        secondRules.seasonNumber = 2
        let first = tournament(format: .league, status: "completed", id: firstID, rules: firstRules)
        let second = tournament(format: .league, status: "active", id: secondID, rules: secondRules)
        XCTAssertEqual(ATHLTHTournamentSeasonContinuation.history(current: first, visible: []).map(\.id), [firstID])
        XCTAssertEqual(ATHLTHTournamentSeasonContinuation.history(current: first, visible: [second]).map(\.id), [secondID, firstID])
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
