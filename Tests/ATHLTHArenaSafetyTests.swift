import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHArenaSafetyTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testDeletedMemberKeepsStableSlotAndEarnedPoints() throws {
        let slotID = UUID()
        let seriesID = UUID()
        let payload = """
        {
          "slot_id":"\(slotID.uuidString)",
          "series_id":"\(seriesID.uuidString)",
          "user_id":null,
          "response":"deleted",
          "points":7.5,
          "created_at":"2026-10-11T01:00:00Z"
        }
        """
        let row = try decoder().decode(
            ATHLTHArenaRemoteMember.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(row.id, slotID)
        XCTAssertNil(row.userID)
        XCTAssertTrue(row.isDeleted)
        XCTAssertEqual(row.points, 7.5)
    }

    func testReplacementOfAthletePreservesIndependentSlotID() throws {
        let slotID = UUID()
        let seriesID = UUID()
        let replacementUser = UUID()
        let payload = """
        {
          "slot_id":"\(slotID.uuidString)",
          "series_id":"\(seriesID.uuidString)",
          "user_id":"\(replacementUser.uuidString)",
          "response":"accepted",
          "points":7.5,
          "created_at":"2026-10-11T01:00:00Z"
        }
        """
        let row = try decoder().decode(
            ATHLTHArenaRemoteMember.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(row.id, slotID)
        XCTAssertEqual(row.userID, replacementUser)
        XCTAssertFalse(row.isDeleted)
        XCTAssertEqual(row.points, 7.5)
    }

    func testDeletedOrganizerDoesNotMakeSeriesUnparseable() throws {
        let id = UUID()
        let payload = """
        {
          "id":"\(id.uuidString)",
          "owner_id":null,
          "title":"Friends Arena",
          "scope":"friends",
          "scoring":"winner",
          "duration_days":14,
          "status":"draft"
        }
        """
        let row = try decoder().decode(
            ATHLTHArenaRemoteSeries.self,
            from: Data(payload.utf8)
        )
        XCTAssertNil(row.ownerID)
        XCTAssertEqual(row.id, id)
        XCTAssertEqual(row.scoring, .winner)
    }

    func testClubSeasonCreatedByDeletedUserStillDecodes() throws {
        let seasonID = UUID()
        let clubID = UUID()
        let payload = """
        {
          "id":"\(seasonID.uuidString)",
          "club_id":"\(clubID.uuidString)",
          "title":"Autumn Arena",
          "starts_on":"2026-10-01",
          "ends_on":"2026-11-01",
          "created_by":null
        }
        """
        let season = try decoder().decode(
            ATHLTHArenaClubSeason.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(season.id, seasonID)
        XCTAssertEqual(season.clubID, clubID)
        XCTAssertNil(season.createdBy)
    }

    func testClubSeasonWithActiveCreatorStillDecodes() throws {
        let userID = UUID()
        let payload = """
        {
          "id":"\(UUID().uuidString)",
          "club_id":"\(UUID().uuidString)",
          "title":"Autumn Arena",
          "starts_on":"2026-10-01",
          "ends_on":"2026-11-01",
          "created_by":"\(userID.uuidString)"
        }
        """
        let season = try decoder().decode(
            ATHLTHArenaClubSeason.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(season.createdBy, userID)
    }

    func testDeletedChatAuthorHasNoProfileID() throws {
        let payload = """
        {
          "id":"\(UUID().uuidString)",
          "series_id":"\(UUID().uuidString)",
          "sender_id":null,
          "body":"Melding fra slettet bruker",
          "created_at":"2026-10-11T01:00:00Z"
        }
        """
        let message = try decoder().decode(
            ATHLTHArenaRemoteMessage.self,
            from: Data(payload.utf8)
        )
        XCTAssertNil(message.senderID)
    }
    private func nextAction(
        status: String = "draft",
        response: String? = "accepted",
        organizer: Bool = false,
        rounds: [UUID] = [UUID()],
        approved: Set<UUID> = [],
        allApproved: Bool = false,
        pendingInvites: Int = 0,
        acceptedCount: Int = 2,
        hasRoute: Bool = false,
        pastDeadline: Bool = false
    ) -> ATHLTHArenaNextAction? {
        ATHLTHArenaNextAction.resolve(
            status: status,
            response: response,
            isOrganizer: organizer,
            roundIDs: rounds,
            personallyApproved: approved,
            allRulesApproved: allApproved,
            pendingInvites: pendingInvites,
            acceptedCount: acceptedCount,
            hasRoute: hasRoute,
            deadlinePassed: pastDeadline
        )
    }

    func testArenaRelayCourseUsesFrozenRouteWithoutChangingOwner() {
        let id = UUID(), owner = UUID()
        let snapshot = ChallengeRouteSnapshot(
            routeID: id,
            title: "Stafettløype",
            distanceKilometers: 4.2,
            coordinates: [
                RouteCoordinate(latitude: 59.90, longitude: 10.70,
                                altitude: nil, sequence: 0),
                RouteCoordinate(latitude: 59.91, longitude: 10.72,
                                altitude: nil, sequence: 1)
            ]
        )
        let route = ATHLTHArenaCompetitionCourse.route(
            from: snapshot, ownerID: owner
        )
        XCTAssertEqual(route?.id, id)
        XCTAssertEqual(route?.ownerID, owner)
        XCTAssertEqual(route?.distanceKilometers, 4.2)
        XCTAssertEqual(route?.coordinates.count, 2)
        XCTAssertEqual(route?.visibility, .privateOnly)
        XCTAssertEqual(route?.routeSource, "arena_competition")
    }

    func testArenaRelayCourseRejectsMalformedOrUnsafeCoordinates() {
        let owner = UUID()
        let first = RouteCoordinate(
            latitude: 59.90, longitude: 10.70, altitude: nil, sequence: 0
        )
        let outOfRange = RouteCoordinate(
            latitude: 95, longitude: 10.71, altitude: nil, sequence: 1
        )
        let invalidCourse = ChallengeRouteSnapshot(
            routeID: UUID(),
            title: "Ugyldig",
            distanceKilometers: 5,
            coordinates: [first, outOfRange]
        )
        XCTAssertNil(ATHLTHArenaCompetitionCourse.route(
            from: invalidCourse, ownerID: owner
        ))
        let singlePoint = ChallengeRouteSnapshot(
            routeID: UUID(),
            title: "For kort",
            distanceKilometers: 5,
            coordinates: [first]
        )
        XCTAssertNil(ATHLTHArenaCompetitionCourse.route(
            from: singlePoint, ownerID: owner
        ))
        let invalidDistance = ChallengeRouteSnapshot(
            routeID: UUID(),
            title: "Ugyldig lengde",
            distanceKilometers: .infinity,
            coordinates: [first, first]
        )
        XCTAssertNil(ATHLTHArenaCompetitionCourse.route(
            from: invalidDistance, ownerID: owner
        ))
    }

    private func relayFixture(
        series: UUID, route: UUID, first: [UUID], second: [UUID]
    ) -> [ATHLTHArenaRelayLeg] {
        let firstLegs = first.enumerated().map { offset, slot in
            ATHLTHArenaRelayLeg(
                slotID: slot, seriesID: series, teamIndex: 1,
                legOrder: offset + 1, routeRoundID: route
            )
        }
        let secondLegs = second.enumerated().map { offset, slot in
            ATHLTHArenaRelayLeg(
                slotID: slot, seriesID: series, teamIndex: 2,
                legOrder: offset + 1, routeRoundID: route
            )
        }
        return firstLegs + secondLegs
    }

    private func relayReport(
        slot: UUID, series: UUID, seconds: Double
    ) -> ATHLTHArenaRelayLegReport {
        ATHLTHArenaRelayLegReport(
            slotID: slot, seriesID: series, elapsedSeconds: seconds,
            submittedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    func testRelayShowsNoTotalUntilAllLegsReport() {
        let series = UUID(), route = UUID()
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let stages = relayFixture(series: series, route: route,
                                  first: [a,b], second: [c,d])
        let partial = ATHLTHArenaRelayProgress.team(
            1, legs: stages,
            reports: [relayReport(slot: a, series: series, seconds: 550)]
        )
        XCTAssertEqual(partial?.completedLegs, 1)
        XCTAssertEqual(partial?.totalLegs, 2)
        XCTAssertNil(partial?.completeTotalSeconds)

        let complete = ATHLTHArenaRelayProgress.team(
            1, legs: stages, reports: [
                relayReport(slot: a, series: series, seconds: 550),
                relayReport(slot: b, series: series, seconds: 660)
            ]
        )
        XCTAssertEqual(complete?.completeTotalSeconds, 1210)
        XCTAssertNil(ATHLTHArenaRelayProgress.team(
            2, legs: stages, reports: []
        )?.completeTotalSeconds)
    }

    func testRelayIgnoresDuplicateForeignOrInvalidTimes() {
        let series = UUID(), route = UUID()
        let a = UUID(), b = UUID()
        let stages = relayFixture(series: series, route: route,
                                  first: [a,b], second: [UUID(),UUID()])
        let reports = [
            relayReport(slot: a, series: series, seconds: 300),
            relayReport(slot: a, series: series, seconds: 250),
            relayReport(slot: b, series: UUID(), seconds: 350),
            relayReport(slot: UUID(), series: series, seconds: 20),
            relayReport(slot: b, series: series, seconds: .infinity)
        ]
        let progress = ATHLTHArenaRelayProgress.team(
            1, legs: stages, reports: reports
        )
        XCTAssertEqual(progress?.completedLegs, 0)
        XCTAssertNil(progress?.completeTotalSeconds)
    }

    func testRelayNextUnreportedLegFollowsAgreedOrderNotReportedOrder() {
        let series = UUID(), route = UUID()
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let stages = relayFixture(
            series: series, route: route,
            first: [a,b], second: [c,d]
        )
        XCTAssertEqual(
            ATHLTHArenaRelayProgress.nextUnreportedLeg(
                for: 1, legs: stages, reports: []
            )?.slotID, a
        )
        // A future stage being reported does not imply physical baton movement.
        XCTAssertEqual(
            ATHLTHArenaRelayProgress.nextUnreportedLeg(
                for: 1, legs: stages,
                reports: [relayReport(slot: b, series: series, seconds: 650)]
            )?.slotID, a
        )
        XCTAssertEqual(
            ATHLTHArenaRelayProgress.nextUnreportedLeg(
                for: 1, legs: stages,
                reports: [relayReport(slot: a, series: series, seconds: 500)]
            )?.slotID, b
        )
        XCTAssertNil(ATHLTHArenaRelayProgress.nextUnreportedLeg(
            for: 1, legs: stages, reports: [
                relayReport(slot: a, series: series, seconds: 500),
                relayReport(slot: b, series: series, seconds: 650)
            ]
        ))
    }

    func testRelayNextUnreportedRejectsInvalidAndDuplicateReports() {
        let series = UUID(), route = UUID()
        let a = UUID(), b = UUID()
        let stages = relayFixture(
            series: series, route: route,
            first: [a,b], second: [UUID(),UUID()]
        )
        XCTAssertEqual(
            ATHLTHArenaRelayProgress.nextUnreportedLeg(
                for: 1, legs: stages,
                reports: [relayReport(slot: a, series: UUID(), seconds: 400)]
            )?.slotID, a
        )
        XCTAssertEqual(
            ATHLTHArenaRelayProgress.nextUnreportedLeg(
                for: 1, legs: stages,
                reports: [
                    relayReport(slot: a, series: series, seconds: 400),
                    relayReport(slot: a, series: series, seconds: 410)
                ]
            )?.slotID, a
        )
        XCTAssertNil(ATHLTHArenaRelayProgress.nextUnreportedLeg(
            for: 0, legs: stages, reports: []
        ))
    }

    func testRelayRejectsMalformedPlanBeforeShowingResults() {
        let series = UUID(), route = UUID(), a = UUID(), b = UUID()
        let valid = relayFixture(series: series, route: route,
                                 first: [a,b], second: [UUID(),UUID()])
        let duplicate = [valid[0], valid[0], valid[2], valid[3]]
        XCTAssertNil(ATHLTHArenaRelayProgress.team(
            1, legs: duplicate, reports: []
        ))
        XCTAssertNil(ATHLTHArenaRelayProgress.team(
            0, legs: valid, reports: []
        ))
    }

    func testRelayComparisonRequiresBothCompleteTeams() {
        let series = UUID(), route = UUID()
        let slots = (0..<4).map { _ in UUID() }
        let legs = relayFixture(
            series: series, route: route,
            first: Array(slots.prefix(2)), second: Array(slots.suffix(2))
        )
        let partial = [
            relayReport(slot: slots[0], series: series, seconds: 300),
            relayReport(slot: slots[1], series: series, seconds: 400),
            relayReport(slot: slots[2], series: series, seconds: 350)
        ]
        XCTAssertNil(ATHLTHArenaRelayProgress.provisionalComparison(
            legs: legs, reports: partial
        ))
        let complete = partial + [
            relayReport(slot: slots[3], series: series, seconds: 450)
        ]
        let candidate = ATHLTHArenaRelayProgress.provisionalComparison(
            legs: legs, reports: complete
        )
        XCTAssertEqual(candidate?.firstTeamSeconds, 700)
        XCTAssertEqual(candidate?.secondTeamSeconds, 800)
        XCTAssertEqual(candidate?.leadingTeam, 1)
        XCTAssertEqual(candidate?.marginSeconds, 100)
    }

    func testRelayComparisonDoesNotInventWinnerForNearTie() {
        let series = UUID(), route = UUID()
        let slots = (0..<4).map { _ in UUID() }
        let legs = relayFixture(
            series: series, route: route,
            first: Array(slots.prefix(2)), second: Array(slots.suffix(2))
        )
        let times = [320.0, 400.0, 350.0, 370.3]
        let reports = zip(slots, times).map { slot, seconds in
            relayReport(slot: slot, series: series, seconds: seconds)
        }
        let result = ATHLTHArenaRelayProgress.provisionalComparison(
            legs: legs, reports: reports
        )
        XCTAssertNotNil(result)
        XCTAssertNil(result?.leadingTeam)
    }

    func testRelayComparisonRejectsForeignRouteOrDuplicateAthlete() {
        let series = UUID(), route = UUID()
        let slots = (0..<4).map { _ in UUID() }
        let legs = relayFixture(
            series: series, route: route,
            first: Array(slots.prefix(2)), second: Array(slots.suffix(2))
        )
        let reports = slots.map {
            relayReport(slot: $0, series: series, seconds: 500)
        }
        var modified = legs
        modified[3] = ATHLTHArenaRelayLeg(
            slotID: slots[3], seriesID: series, teamIndex: 2,
            legOrder: 2, routeRoundID: UUID()
        )
        XCTAssertNil(ATHLTHArenaRelayProgress.provisionalComparison(
            legs: modified, reports: reports
        ))
        modified = legs
        modified[3] = ATHLTHArenaRelayLeg(
            slotID: slots[0], seriesID: series, teamIndex: 2,
            legOrder: 2, routeRoundID: route
        )
        XCTAssertNil(ATHLTHArenaRelayProgress.provisionalComparison(
            legs: modified, reports: reports
        ))
    }

    func testRelayComparisonRejectsDuplicateInvalidOrForeignReports() {
        let series = UUID(), route = UUID()
        let slots = (0..<4).map { _ in UUID() }
        let legs = relayFixture(
            series: series, route: route,
            first: Array(slots.prefix(2)), second: Array(slots.suffix(2))
        )
        let base = slots.map {
            relayReport(slot: $0, series: series, seconds: 500)
        }
        XCTAssertNil(ATHLTHArenaRelayProgress.provisionalComparison(
            legs: legs, reports: base + [base[0]]
        ))
        var foreign = base
        foreign[1] = relayReport(slot: slots[1], series: UUID(), seconds: 500)
        XCTAssertNil(ATHLTHArenaRelayProgress.provisionalComparison(
            legs: legs, reports: foreign
        ))
        var invalid = base
        invalid[0] = relayReport(slot: slots[0], series: series, seconds: .infinity)
        XCTAssertNil(ATHLTHArenaRelayProgress.provisionalComparison(
            legs: legs, reports: invalid
        ))
        XCTAssertNil(ATHLTHArenaRelayProgress.reportedTime(
            for: legs[0], reports: base + [base[0]]
        ))
        XCTAssertEqual(ATHLTHArenaRelayProgress.reportedTime(
            for: legs[1], reports: base
        ), 500)
    }

    func testArenaNextActionPrioritizesInvitationAndDoesNotShowForOutsiders() {
        XCTAssertEqual(
            nextAction(response: "invited", organizer: true, rounds: []),
            .respondToInvite
        )
        XCTAssertNil(nextAction(response: nil))
        XCTAssertNil(nextAction(response: "declined"))
    }

    func testArenaNextActionCreatorSetsUpFirstRound() {
        XCTAssertEqual(
            nextAction(organizer: true, rounds: []), .addRound
        )
        XCTAssertEqual(
            nextAction(organizer: false, rounds: []), .waitingForRules
        )
    }

    func testArenaNextActionRequiresPersonalRuleApprovalBeforeStart() {
        let round = UUID()
        XCTAssertEqual(
            nextAction(
                organizer: true,
                rounds: [round],
                approved: [],
                allApproved: true
            ),
            .approveRule(round)
        )
        XCTAssertEqual(
            nextAction(
                organizer: true,
                rounds: [round],
                approved: [round],
                allApproved: true,
                pendingInvites: 1
            ),
            .waitingForInvites
        )
        XCTAssertEqual(
            nextAction(
                organizer: true,
                rounds: [round],
                approved: [round],
                allApproved: false
            ),
            .waitingForRules
        )
    }

    func testArenaNextActionOnlyOrganizerMaySeeStartPrompt() {
        let round = UUID()
        XCTAssertEqual(
            nextAction(
                organizer: true,
                rounds: [round],
                approved: [round],
                allApproved: true
            ),
            .startSeries
        )
        XCTAssertEqual(
            nextAction(
                organizer: false,
                rounds: [round],
                approved: [round],
                allApproved: true
            ),
            .waitingForRules
        )
    }

    func testArenaNextActionDoesNotCallAnExpiredSeriesActive() {
        XCTAssertEqual(
            nextAction(status: "active", hasRoute: true), .runRoute
        )
        XCTAssertEqual(
            nextAction(status: "active", hasRoute: false), .compete
        )
        XCTAssertEqual(
            nextAction(
                status: "active", hasRoute: true, pastDeadline: true
            ),
            .reviewScores
        )
        XCTAssertEqual(
            nextAction(status: "completed"), .finalStandings
        )
        XCTAssertNil(nextAction(status: "cancelled"))
    }

}
