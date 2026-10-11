import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHArenaSafetyTests: XCTestCase {
    func testTeamQuickStartRequiresBalancedMinimumRoster() {
        // Organizer is always the first member. Three invited athletes
        // therefore make two teams of two; two invitees cannot.
        XCTAssertFalse(ATHLTHArenaTeamStartRules.validInviteeCount(0))
        XCTAssertFalse(ATHLTHArenaTeamStartRules.validInviteeCount(1))
        XCTAssertFalse(ATHLTHArenaTeamStartRules.validInviteeCount(2))
        XCTAssertTrue(ATHLTHArenaTeamStartRules.validInviteeCount(3))
        XCTAssertFalse(ATHLTHArenaTeamStartRules.validInviteeCount(4))
        XCTAssertTrue(ATHLTHArenaTeamStartRules.validInviteeCount(5))
        XCTAssertTrue(ATHLTHArenaTeamStartRules.validInviteeCount(19))
        XCTAssertFalse(ATHLTHArenaTeamStartRules.validInviteeCount(20))
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func overviewSeries(
        status: String,
        endsAt: String? = nil,
        completedAt: String? = nil,
        id: UUID = UUID()
    ) throws -> ATHLTHArenaRemoteSeries {
        var fields = [
            "\"id\":\"\(id.uuidString)\"",
            "\"owner_id\":null",
            "\"title\":\"Test competition\"",
            "\"scope\":\"duel\"",
            "\"scoring\":\"winner\"",
            "\"duration_days\":14",
            "\"status\":\"\(status)\""
        ]
        if let endsAt {
            fields.append("\"ends_at\":\"\(endsAt)\"")
        }
        if let completedAt {
            fields.append("\"completed_at\":\"\(completedAt)\"")
        }
        return try decoder().decode(
            ATHLTHArenaRemoteSeries.self,
            from: Data(("{"+fields.joined(separator: ",")+"}").utf8)
        )
    }

    func testArenaHomePutsUrgentCompetitionsFirst() throws {
        let expired = try overviewSeries(
            status: "active", endsAt: "2026-10-11T12:00:00Z"
        )
        let tonight = try overviewSeries(
            status: "active", endsAt: "2026-10-11T23:00:00Z"
        )
        let nextWeek = try overviewSeries(
            status: "active", endsAt: "2026-10-20T12:00:00Z"
        )
        let missingDate = try overviewSeries(status: "active")
        let alreadyDone = try overviewSeries(
            status: "completed", endsAt: "2026-10-11T11:00:00Z"
        )
        let ordered = ATHLTHArenaSeriesOverview.orderedActive(
            [missingDate, nextWeek, tonight, alreadyDone, expired]
        )
        XCTAssertEqual(
            ordered.map(\.id),
            [expired.id, tonight.id, nextWeek.id, missingDate.id]
        )
    }

    func testArenaHomeDeadlineUsesRealMinutesHoursAndDays() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func subject(_ delta: TimeInterval) throws -> ATHLTHArenaRemoteSeries {
            let series = try overviewSeries(
                status: "active",
                endsAt: ISO8601DateFormatter().string(
                    from: now.addingTimeInterval(delta)
                )
            )
            return series
        }
        XCTAssertEqual(
            ATHLTHArenaSeriesOverview.urgency(for: try subject(-1), at: now),
            .review
        )
        XCTAssertEqual(
            ATHLTHArenaSeriesOverview.urgency(for: try subject(59), at: now),
            .minutes(1)
        )
        XCTAssertEqual(
            ATHLTHArenaSeriesOverview.urgency(for: try subject(3_600), at: now),
            .hours(1)
        )
        XCTAssertEqual(
            ATHLTHArenaSeriesOverview.urgency(for: try subject(48 * 3_600), at: now),
            .days(2)
        )
        XCTAssertNil(
            ATHLTHArenaSeriesOverview.urgency(for: try subject(4 * 86_400), at: now)
        )
    }

    func testArenaHomeCompletedHistoryNewestFirst() throws {
        let early = try overviewSeries(
            status: "completed", completedAt: "2026-09-01T09:00:00Z"
        )
        let late = try overviewSeries(
            status: "completed", completedAt: "2026-10-11T19:00:00Z"
        )
        let active = try overviewSeries(status: "active")
        XCTAssertEqual(
            ATHLTHArenaSeriesOverview.orderedCompleted(
                [early, active, late]
            ).map(\.id),
            [late.id, early.id]
        )
        XCTAssertNil(
            ATHLTHArenaSeriesOverview.urgency(for: late, at: Date())
        )
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

    func testClubSeasonPhaseHasInclusiveFinalDay() {
        XCTAssertEqual(
            ATHLTHArenaSeasonPresentation.phase(
                startsOn: "2026-10-01", endsOn: "2026-10-31",
                today: "2026-09-30"
            ), .upcoming
        )
        XCTAssertEqual(
            ATHLTHArenaSeasonPresentation.phase(
                startsOn: "2026-10-01", endsOn: "2026-10-31",
                today: "2026-10-01"
            ), .active
        )
        XCTAssertEqual(
            ATHLTHArenaSeasonPresentation.phase(
                startsOn: "2026-10-01", endsOn: "2026-10-31",
                today: "2026-10-31"
            ), .active
        )
        XCTAssertEqual(
            ATHLTHArenaSeasonPresentation.phase(
                startsOn: "2026-10-01", endsOn: "2026-10-31",
                today: "2026-11-01"
            ), .completed
        )
    }

    func testClubSeasonLeadersPreserveJointFirstPlace() {
        let first = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: 12, competitions: 3
        )
        let second = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: 12, competitions: 2
        )
        let third = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: 8, competitions: 3
        )
        let leaders = ATHLTHArenaSeasonPresentation.leadingAthletes(
            [third, second, first]
        )
        XCTAssertEqual(Set(leaders.map(\.userID)), Set([first.userID, second.userID]))
    }

    func testClubSeasonZeroPointsCannotProduceChampion() {
        let rows = [
            ATHLTHArenaSeasonStandingsRow(
                userID: UUID(), points: 0, competitions: 1
            ),
            ATHLTHArenaSeasonStandingsRow(
                userID: UUID(), points: 0, competitions: 0
            )
        ]
        XCTAssertTrue(ATHLTHArenaSeasonPresentation.leadingAthletes(rows).isEmpty)
    }

    func testSeasonChampionRequiresTrustedServerCloseout() {
        XCTAssertTrue(ATHLTHArenaSeasonPresentation.canDeclareChampion(
            phase: .completed, linkedCompetitionCount: 2,
            incompleteCompetitionCount: 0, unresolvedCompetitionCount: 0
        ))
        XCTAssertFalse(ATHLTHArenaSeasonPresentation.canDeclareChampion(
            phase: .active, linkedCompetitionCount: 2,
            incompleteCompetitionCount: 0, unresolvedCompetitionCount: 0
        ))
        XCTAssertFalse(ATHLTHArenaSeasonPresentation.canDeclareChampion(
            phase: .upcoming, linkedCompetitionCount: 2,
            incompleteCompetitionCount: 0, unresolvedCompetitionCount: 0
        ))
        XCTAssertFalse(ATHLTHArenaSeasonPresentation.canDeclareChampion(
            phase: .completed, linkedCompetitionCount: 0,
            incompleteCompetitionCount: 0, unresolvedCompetitionCount: 0
        ))
        XCTAssertFalse(ATHLTHArenaSeasonPresentation.canDeclareChampion(
            phase: .completed, linkedCompetitionCount: 2,
            incompleteCompetitionCount: 1, unresolvedCompetitionCount: 0
        ))
        XCTAssertFalse(ATHLTHArenaSeasonPresentation.canDeclareChampion(
            phase: .completed, linkedCompetitionCount: 2,
            incompleteCompetitionCount: 0, unresolvedCompetitionCount: 1
        ))
    }

    func testSeasonCompetitionRanksPreserveTiesAndSkipPositions() {
        let a = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: 12, competitions: 3
        )
        let b = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: 12, competitions: 2
        )
        let c = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: 8, competitions: 1
        )
        let d = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: 0, competitions: 0
        )
        let input = [c, d, b, a]
        let ordered = ATHLTHArenaSeasonPresentation.orderedStandings(input)
        XCTAssertEqual(ordered.map(\.points), [12, 12, 8, 0])
        XCTAssertEqual(ATHLTHArenaSeasonPresentation.competitiveRank(
            of: a, among: ordered
        ), 1)
        XCTAssertEqual(ATHLTHArenaSeasonPresentation.competitiveRank(
            of: b, among: ordered
        ), 1)
        XCTAssertEqual(ATHLTHArenaSeasonPresentation.competitiveRank(
            of: c, among: ordered
        ), 3)
        XCTAssertNil(ATHLTHArenaSeasonPresentation.competitiveRank(
            of: d, among: ordered
        ))
    }

    func testSeasonRankingDoesNotAssignFirstPlaceToInvalidPoints() {
        let invalid = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: .nan, competitions: 1
        )
        let zero = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: 0, competitions: 1
        )
        let valid = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: 3, competitions: 1
        )
        XCTAssertNil(ATHLTHArenaSeasonPresentation.competitiveRank(
            of: invalid, among: [invalid, zero, valid]
        ))
        XCTAssertNil(ATHLTHArenaSeasonPresentation.competitiveRank(
            of: zero, among: [invalid, zero, valid]
        ))
        XCTAssertEqual(ATHLTHArenaSeasonPresentation.competitiveRank(
            of: valid, among: [invalid, zero, valid]
        ), 1)
    }

    func testSeasonStandingsNeverPromoteMalformedScores() {
        let valid = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: 6, competitions: 1
        )
        let missing = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: .nan, competitions: 1
        )
        let invalid = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: -.infinity, competitions: 1
        )
        let negative = ATHLTHArenaSeasonStandingsRow(
            userID: UUID(), points: -5, competitions: 1
        )
        let ordered = ATHLTHArenaSeasonPresentation.orderedStandings(
            [missing, invalid, negative, valid]
        )
        XCTAssertEqual(ordered.first?.userID, valid.userID)
        XCTAssertNil(ATHLTHArenaSeasonPresentation.competitiveRank(
            of: missing, among: ordered
        ))
        XCTAssertNil(ATHLTHArenaSeasonPresentation.competitiveRank(
            of: negative, among: ordered
        ))
    }

    func testSeasonPersonalProgressNeverUsesInvalidHistoricalPoints() {
        XCTAssertNil(ATHLTHArenaSeasonPresentation.visiblePoints(.nan))
        XCTAssertNil(ATHLTHArenaSeasonPresentation.visiblePoints(.infinity))
        XCTAssertNil(ATHLTHArenaSeasonPresentation.visiblePoints(-4))
        XCTAssertEqual(ATHLTHArenaSeasonPresentation.visiblePoints(0), 0)
        XCTAssertEqual(ATHLTHArenaSeasonPresentation.visiblePoints(12), 12)
        XCTAssertNil(ATHLTHArenaSeasonPresentation.pointsToCatchLeader(
            ownPoints: .nan, leaderPoints: 14
        ))
        XCTAssertNil(ATHLTHArenaSeasonPresentation.pointsToCatchLeader(
            ownPoints: 8, leaderPoints: .infinity
        ))
        XCTAssertEqual(ATHLTHArenaSeasonPresentation.pointsToCatchLeader(
            ownPoints: 8, leaderPoints: 14
        ), 6)
        XCTAssertEqual(ATHLTHArenaSeasonPresentation.pointsToCatchLeader(
            ownPoints: 14, leaderPoints: 14
        ), 0)
        XCTAssertEqual(ATHLTHArenaSeasonPresentation.pointsToCatchLeader(
            ownPoints: 20, leaderPoints: 14
        ), 0)
    }

    func testSeasonProgressUsesWholeCalendarDaysIncludingLastDay() {
        let first = ATHLTHArenaSeasonPresentation.progress(
            startsOn: "2026-10-01", endsOn: "2026-10-31", today: "2026-10-01"
        )
        XCTAssertEqual(first?.fraction ?? -1, 1.0 / 31.0, accuracy: 0.000001)
        XCTAssertEqual(first?.daysRemaining, 30)

        let last = ATHLTHArenaSeasonPresentation.progress(
            startsOn: "2026-10-01", endsOn: "2026-10-31", today: "2026-10-31"
        )
        XCTAssertEqual(last?.fraction ?? -1, 1, accuracy: 0.000001)
        XCTAssertEqual(last?.daysRemaining, 0)

        let before = ATHLTHArenaSeasonPresentation.progress(
            startsOn: "2026-10-01", endsOn: "2026-10-31", today: "2026-09-29"
        )
        XCTAssertEqual(before?.fraction ?? -1, 0, accuracy: 0.000001)
        XCTAssertEqual(before?.daysToStart, 2)

        let after = ATHLTHArenaSeasonPresentation.progress(
            startsOn: "2026-10-01", endsOn: "2026-10-31", today: "2026-11-02"
        )
        XCTAssertEqual(after?.fraction ?? -1, 1, accuracy: 0.000001)
    }

    func testSeasonProgressRejectsReversedOrInvalidDates() {
        XCTAssertNil(ATHLTHArenaSeasonPresentation.progress(
            startsOn: "2026-10-31", endsOn: "2026-10-01", today: "2026-10-12"
        ))
        XCTAssertNil(ATHLTHArenaSeasonPresentation.progress(
            startsOn: "2026-02-30", endsOn: "2026-03-01", today: "2026-02-28"
        ))
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

    private func seasonSeries(
        status: String,
        title: String = "Arena round",
        starts: Date? = nil,
        completed: Date? = nil,
        completionReason: String? = nil
    ) -> ATHLTHArenaRemoteSeries {
        ATHLTHArenaRemoteSeries(
            id: UUID(),
            ownerID: UUID(),
            clubID: UUID(),
            title: title,
            scope: .club,
            scoring: .winner,
            durationDays: 14,
            status: status,
            startsAt: starts,
            endsAt: nil,
            completedAt: completed,
            completionReason: completionReason
        )
    }

    func testSeasonCompetitionAgendaPrioritizesActiveThenPreparingThenCompleted() {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        let completed = seasonSeries(
            status: "completed", title: "Old competition",
            completed: now.addingTimeInterval(-86_400)
        )
        let pending = seasonSeries(
            status: "draft", title: "Upcoming competition",
            starts: now.addingTimeInterval(2 * 86_400)
        )
        let active = seasonSeries(
            status: "active", title: "Current competition",
            starts: now
        )
        let sorted = ATHLTHArenaSeasonCompetitionTimeline.ordered(
            [completed, pending, active]
        )
        XCTAssertEqual(sorted.map(\.id), [active.id, pending.id, completed.id])
        XCTAssertEqual(ATHLTHArenaSeasonCompetitionTimeline.phase(active), .active)
        XCTAssertEqual(ATHLTHArenaSeasonCompetitionTimeline.phase(pending), .preparing)
        XCTAssertEqual(ATHLTHArenaSeasonCompetitionTimeline.phase(completed), .completed)
    }

    func testSeasonAgendaOrdersCompletedMostRecentFirst() {
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        let old = seasonSeries(
            status: "completed", title: "A",
            completed: date.addingTimeInterval(-100_000)
        )
        let newest = seasonSeries(
            status: "completed", title: "Z",
            completed: date
        )
        XCTAssertEqual(
            ATHLTHArenaSeasonCompetitionTimeline.ordered([old, newest]).map(\.id),
            [newest.id, old.id]
        )
    }

    func testSeasonAgendaTreatsUnknownStatusAsUnavailableNotActive() {
        let uncertain = seasonSeries(status: "unknown")
        let active = seasonSeries(status: "active")
        let order = ATHLTHArenaSeasonCompetitionTimeline.ordered([uncertain, active])
        XCTAssertEqual(order.map(\.id), [active.id, uncertain.id])
        XCTAssertEqual(ATHLTHArenaSeasonCompetitionTimeline.phase(uncertain), .unavailable)
        XCTAssertNotEqual(
            ATHLTHArenaSeasonCompetitionTimeline.status(uncertain),
            ATHLTHArenaSeasonCompetitionTimeline.status(active)
        )
    }

    func testClubSeasonDetachOnlyAllowsDraftsForAdminsBeforeDeadline() {
        let draft = seasonSeries(status: "draft")
        let active = seasonSeries(status: "active")
        let complete = seasonSeries(status: "completed")
        let eligible = ATHLTHArenaSeasonCompetitionTimeline.canDetach(
            draft, endsOn: "2026-12-31", today: "2026-11-01",
            canManage: true
        )
        XCTAssertTrue(eligible)
        XCTAssertFalse(ATHLTHArenaSeasonCompetitionTimeline.canDetach(
            draft, endsOn: "2026-12-31", today: "2026-11-01",
            canManage: false
        ))
        XCTAssertFalse(ATHLTHArenaSeasonCompetitionTimeline.canDetach(
            active, endsOn: "2026-12-31", today: "2026-11-01",
            canManage: true
        ))
        XCTAssertFalse(ATHLTHArenaSeasonCompetitionTimeline.canDetach(
            complete, endsOn: "2026-12-31", today: "2026-11-01",
            canManage: true
        ))
        XCTAssertFalse(ATHLTHArenaSeasonCompetitionTimeline.canDetach(
            draft, endsOn: "2026-10-30", today: "2026-11-01",
            canManage: true
        ))
    }

    private func clubSeason(
        _ title: String,
        start: String,
        end: String,
        id: UUID = UUID()
    ) -> ATHLTHArenaClubSeason {
        ATHLTHArenaClubSeason(
            id: id,
            clubID: UUID(),
            title: title,
            startsOn: start,
            endsOn: end,
            createdBy: nil
        )
    }

    func testSeasonHomePrioritizesActiveAndUpcomingOverRecentHistory() {
        let active = clubSeason(
            "Active", start: "2026-10-01", end: "2026-10-25"
        )
        let old = clubSeason(
            "Finished", start: "2026-09-01", end: "2026-09-30"
        )
        let soon = clubSeason(
            "Next", start: "2026-10-12", end: "2026-10-31"
        )
        let history = [
            old,
            clubSeason("Older", start: "2026-08-01", end: "2026-08-31"),
            clubSeason("Much older", start: "2026-07-01", end: "2026-07-31"),
            clubSeason("Historic", start: "2026-06-01", end: "2026-06-30")
        ]
        XCTAssertEqual(
            ATHLTHArenaSeasonPresentation.prioritizedSeasons(
                history + [soon, active],
                today: "2026-10-11"
            ).prefix(4).map(\.id),
            [active.id, soon.id, old.id, history[1].id]
        )
    }

    func testSeasonHomeShowsNearestActiveDeadlineAndUpcomingStartFirst() {
        let activeLate = clubSeason(
            "Long", start: "2026-10-01", end: "2026-12-31"
        )
        let activeSoon = clubSeason(
            "Soon", start: "2026-10-10", end: "2026-10-11"
        )
        let nextMonth = clubSeason(
            "Later", start: "2026-11-01", end: "2026-11-30"
        )
        let tomorrow = clubSeason(
            "Tomorrow", start: "2026-10-12", end: "2026-10-15"
        )
        let order = ATHLTHArenaSeasonPresentation.prioritizedSeasons(
            [nextMonth, activeLate, tomorrow, activeSoon],
            today: "2026-10-11"
        )
        XCTAssertEqual(
            order.map(\.id),
            [activeSoon.id, activeLate.id, tomorrow.id, nextMonth.id]
        )
    }

    func testCompletedSeasonHistoryOrdersLatestFirstAndTiesAreStable() {
        let recent = clubSeason(
            "Recent", start: "2026-08-01", end: "2026-09-30"
        )
        let old = clubSeason(
            "Old", start: "2026-07-01", end: "2026-07-31"
        )
        let rows = [old, recent]
        let first = ATHLTHArenaSeasonPresentation.prioritizedSeasons(
            rows, today: "2026-10-11"
        )
        let second = ATHLTHArenaSeasonPresentation.prioritizedSeasons(
            Array(rows.reversed()), today: "2026-10-11"
        )
        XCTAssertEqual(first.map(\.id), [recent.id, old.id])
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testUnresolvedSeasonCompetitionHasDistinctStatus() {
        let unresolved = seasonSeries(
            status: "completed", completionReason: "deadline_unresolved"
        )
        let settled = seasonSeries(status: "completed")
        XCTAssertNotEqual(
            ATHLTHArenaSeasonCompetitionTimeline.status(unresolved),
            ATHLTHArenaSeasonCompetitionTimeline.status(settled)
        )
    }


}
