import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHArenaV3TournamentTests: XCTestCase {
    private func athletes(_ names: [String]) -> [ATHLTHTournamentParticipant] {
        names.map { ATHLTHTournamentParticipant(id: UUID(), username: $0) }
    }

    func testPendingInvitationDoesNotRequireAcceptedMembership() {
        XCTAssertTrue(ATHLTHArenaV3Filter.invitations.includes(
            status: "inviting", isMember: false, isInvited: true))
        XCTAssertFalse(ATHLTHArenaV3Filter.active.includes(
            status: "inviting", isMember: true, isInvited: true))
        XCTAssertFalse(ATHLTHArenaV3Filter.invitations.includes(
            status: "inviting", isMember: false, isInvited: false))
    }

    func testCompetitionHubHistoryAndActiveAreSeparate() {
        for status in ["completed", "cancelled"] {
            XCTAssertTrue(ATHLTHArenaV3Filter.finished.includes(
                status: status, isMember: true, isInvited: false))
            XCTAssertFalse(ATHLTHArenaV3Filter.active.includes(
                status: status, isMember: true, isInvited: false))
        }
        XCTAssertTrue(ATHLTHArenaV3Filter.active.includes(
            status: "active", isMember: true, isInvited: false))
        XCTAssertFalse(ATHLTHArenaV3Filter.finished.includes(
            status: "active", isMember: true, isInvited: false))
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

    func testPracticeRoundsNeverScoreOrEliminateInAnyFormat() {
        let practice = ATHLTHTournamentWarmupRound(title: "Prøverunde")
        XCTAssertFalse(practice.countsForPoints)
        XCTAssertFalse(practice.countsForAdvancement)
        XCTAssertFalse(practice.mayEliminate)

        for format in ATHLTHTournamentFormat.allCases {
            let draft = ATHLTHTournamentDraft(
                ownerID: UUID(), clubID: nil,
                title: "Test", format: format,
                groupSize: 4, qualifiersPerGroup: 2,
                participants: athletes(["A", "B"]),
                warmupRounds: [practice]
            )
            XCTAssertEqual(draft.warmupRounds.count, 1)
            XCTAssertFalse(draft.warmupRounds[0].countsForPoints)
            XCTAssertFalse(draft.warmupRounds[0].mayEliminate)
        }
    }

    func testSeasonLinkedDraftSurvivesEncoding() throws {
        let clubID = UUID()
        let seasonID = UUID()
        let practice = ATHLTHTournamentWarmupRound(title: "Første testløp")
        let draft = ATHLTHTournamentDraft(
            ownerID: UUID(), clubID: clubID, seasonID: seasonID,
            title: "Klubbliga", format: .groups,
            groupSize: 4, qualifiersPerGroup: 2,
            participants: athletes(["A", "B", "C", "D"]),
            warmupRounds: [practice]
        )
        let restored = try JSONDecoder().decode(
            ATHLTHTournamentDraft.self,
            from: JSONEncoder().encode(draft)
        )
        XCTAssertEqual(restored.clubID, clubID)
        XCTAssertEqual(restored.seasonID, seasonID)
        XCTAssertEqual(restored.warmupRounds.map(\.title), ["Første testløp"])
    }

    func testOldTournamentDraftWithoutSeasonOrWarmupsStillDecodes() throws {
        let original = ATHLTHTournamentDraft(
            ownerID: UUID(), clubID: UUID(), title: "Gammel cup",
            format: .cup, groupSize: 4, qualifiersPerGroup: 2,
            participants: athletes(["A", "B"])
        )
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original))
                as? [String: Any]
        )
        payload.removeValue(forKey: "seasonID")
        payload.removeValue(forKey: "warmupRounds")
        let oldData = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(ATHLTHTournamentDraft.self,
                                               from: oldData)
        XCTAssertNil(decoded.seasonID)
        XCTAssertTrue(decoded.warmupRounds.isEmpty)
        XCTAssertEqual(decoded.id, original.id)
    }

    func testPersonalTournamentCannotClaimClubSeason() {
        let draft = ATHLTHTournamentDraft(
            ownerID: UUID(), clubID: nil, seasonID: UUID(),
            title: "Åpen cup", format: .cup,
            groupSize: 4, qualifiersPerGroup: 2,
            participants: athletes(["A", "B"])
        )
        XCTAssertNil(draft.seasonID)
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

    func testConfigurableCompetitionMeasuresRoundTripWithoutPublishing() throws {
        let libraryID = UUID()
        let routeID = UUID()
        var strength = ATHLTHCompetitionMeasureDraft(activity: .strength,
            measure: .heaviestForReps, libraryID: libraryID, libraryName: "Benkpress")
        strength.repetitions = 10
        let intervals = ATHLTHCompetitionMeasureDraft(activity: .running, measure: .intervalDistance)
        let route = ATHLTHCompetitionMeasureDraft(activity: .running,
            measure: .routeTime, routeID: routeID, routeName: "Testløype")
        var race = ATHLTHCompetitionRaceRules()
        race.measureDrafts = [strength, intervals, route]
        XCTAssertTrue(race.isValid)
        XCTAssertFalse(race.isOperational)
        let decoded = try JSONDecoder().decode(ATHLTHCompetitionRaceRules.self,
            from: JSONEncoder().encode(race))
        XCTAssertEqual(decoded.plannedMeasures, [strength, intervals, route])
        XCTAssertEqual(decoded.plannedMeasures.first?.libraryID, libraryID)
        XCTAssertEqual(decoded.plannedMeasures.last?.routeID, routeID)
        XCTAssertFalse(decoded.isOperational)
    }

    func testConfiguredMeasuresRejectInvalidTargetsAndDuplicateEntries() {
        var strength = ATHLTHCompetitionMeasureDraft(activity: .strength, measure: .heaviestForReps)
        XCTAssertFalse(strength.isValid)
        strength.libraryID = UUID()
        strength.libraryName = "Benkpress"
        strength.repetitions = 0
        XCTAssertFalse(strength.isValid)
        strength.repetitions = 10
        XCTAssertTrue(strength.isValid)
        var race = ATHLTHCompetitionRaceRules()
        race.measureDrafts = [strength, strength]
        XCTAssertFalse(race.isValid)
        var wrongActivity = ATHLTHCompetitionMeasureDraft(activity: .walking, measure: .sprint)
        XCTAssertFalse(wrongActivity.isValid)
        wrongActivity.measure = .distanceInTime
        XCTAssertTrue(wrongActivity.isValid)
        wrongActivity.durationSeconds = 0
        XCTAssertFalse(wrongActivity.isValid)
    }

    func testConfiguredRouteDoesNotRequireInventedLibraryID() {
        var route = ATHLTHCompetitionMeasureDraft(activity: .running, measure: .routeSpeed,
            routeID: UUID(), routeName: "Runde")
        XCTAssertTrue(route.isValid)
        route.libraryID = UUID()
        XCTAssertFalse(route.isValid)
        route.libraryID = nil
        var settings = ATHLTHTournamentCompetitionSettings()
        settings.selectedExerciseIDs = []
        settings.race.measureDrafts = [route]
        XCTAssertTrue(settings.isValid)
        XCTAssertFalse(settings.race.isOperational)
    }

    func testOldRaceRulesStillDecodeWithNoConfiguredMeasures() throws {
        let old = try JSONDecoder().decode(ATHLTHCompetitionRaceRules.self, from: Data("{}".utf8))
        XCTAssertTrue(old.plannedMeasures.isEmpty)
        XCTAssertTrue(old.isValid)
        XCTAssertTrue(old.isOperational)
    }
}
