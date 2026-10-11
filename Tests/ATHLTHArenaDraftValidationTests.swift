import Foundation
import XCTest
@testable import ATHLTH

/// Phase 1: publishing must reject malformed drafts locally, while the
/// backend independently enforces the authoritative invite/start rules.
final class ATHLTHArenaDraftValidationTests: XCTestCase {
    private func validDraft() -> ATHLTHArenaCompetitionDraft {
        ATHLTHArenaCompetitionDraft(
            ownerID: UUID(),
            title: "Monday Arena",
            scope: .duel,
            scoring: .winner,
            durationDays: 14,
            participantIDs: [UUID()],
            clubID: nil,
            rounds: [
                ATHLTHArenaRoundDraft(
                    template: .fastest5K,
                    title: "Fastest 5 km",
                    rules: "Run a verified 5 km activity."
                )
            ]
        )
    }

    func testValidDuelCanBePublished() {
        XCTAssertNil(ATHLTHArenaDraftValidation.issue(for: validDraft()))
    }

    func testInvalidTitleAndDurationAreRejectedBeforeSending() {
        var draft = validDraft()
        draft.title = " \n "
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .missingTitle)
        draft.title = String(repeating: "A", count: 81)
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .titleTooLong)
        draft.title = "Valid"
        draft.durationDays = 91
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .invalidDuration)
    }

    func testInviteeConstraintsMatchServerLimits() {
        var draft = validDraft()
        let rival = draft.participantIDs[0]
        draft.participantIDs = []
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .invalidInvitees)
        draft.participantIDs = [rival, UUID()]
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .duelNeedsOneOpponent)
        draft.participantIDs = [draft.ownerID]
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .invalidInvitees)
        draft.participantIDs = [rival, rival]
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .invalidInvitees)
        draft.scope = .friends
        draft.participantIDs = (0..<21).map { _ in UUID() }
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .invalidInvitees)
        draft.participantIDs = Array(draft.participantIDs.prefix(20))
        XCTAssertNil(ATHLTHArenaDraftValidation.issue(for: draft))
    }

    func testClubNeedsSelectedClub() {
        var draft = validDraft()
        draft.scope = .club
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .missingClub)
        draft.clubID = UUID()
        XCTAssertNil(ATHLTHArenaDraftValidation.issue(for: draft))
    }

    func testRoundCountAndRoundIdentityAreChecked() {
        var draft = validDraft()
        let first = draft.rounds[0]
        draft.rounds = []
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .missingRounds)
        draft.rounds = (0..<17).map { _ in
            ATHLTHArenaRoundDraft(
                template: .fastest5K,
                title: "5 km",
                rules: "Fastest eligible run wins."
            )
        }
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .tooManyRounds)
        draft.rounds = [first, first]
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .invalidRound)
    }

    func testRoundTextAndDistanceAreValidated() {
        var draft = validDraft()
        draft.rounds[0].rules = String(repeating: "r", count: 601)
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .invalidRound)
        draft.rounds = [
            ATHLTHArenaRoundDraft(
                template: .fastestDistance,
                title: "Custom distance",
                rules: "Fastest run",
                targetDistanceMeters: nil
            )
        ]
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .invalidDistance)
        draft.rounds[0].targetDistanceMeters = .infinity
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .invalidDistance)
        draft.rounds[0].targetDistanceMeters = 1_000
        XCTAssertNil(ATHLTHArenaDraftValidation.issue(for: draft))
    }

    func testRouteRoundRequiresAnActualRoute() {
        var draft = validDraft()
        draft.rounds = [
            ATHLTHArenaRoundDraft(
                template: .fastestRoute,
                title: "Route",
                rules: "Follow the route",
                targetDistanceMeters: 5_000
            )
        ]
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .missingRoute)
    }


    func testMalformedRouteCoordinatesAreRejectedBeforeInvitations() {
        var draft = validDraft()
        let start = RouteCoordinate(
            latitude: 59.90, longitude: 10.70, altitude: nil, sequence: 0
        )
        let impossible = RouteCoordinate(
            latitude: 91, longitude: 10.71, altitude: nil, sequence: 1
        )
        draft.rounds = [
            ATHLTHArenaRoundDraft(
                template: .fastestRoute,
                title: "Route",
                rules: "Follow the agreed route",
                targetDistanceMeters: 5_000,
                routeSnapshot: ChallengeRouteSnapshot(
                    routeID: UUID(),
                    title: "Invalid",
                    distanceKilometers: 5,
                    coordinates: [start, impossible]
                )
            )
        ]
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .missingRoute)
        draft.rounds[0].routeSnapshot = ChallengeRouteSnapshot(
            routeID: UUID(),
            title: "Valid",
            distanceKilometers: 5,
            coordinates: [
                start,
                RouteCoordinate(
                    latitude: 59.91, longitude: 10.72, altitude: nil, sequence: 1
                )
            ]
        )
        XCTAssertNil(ATHLTHArenaDraftValidation.issue(for: draft))
    }

    func testRouteSnapshotPointLimitRejectsOversizedSharedRoutes() {
        var draft = validDraft()
        let coordinates = (0..<1_501).map { index in
            RouteCoordinate(
                latitude: 59.90,
                longitude: 10.70 + Double(index) * 0.00001,
                altitude: nil,
                sequence: index
            )
        }
        draft.rounds = [
            ATHLTHArenaRoundDraft(
                template: .fastestRoute,
                title: "Long route preview",
                rules: "Follow the route",
                targetDistanceMeters: 5_000,
                routeSnapshot: ChallengeRouteSnapshot(
                    routeID: UUID(),
                    title: "Too many points",
                    distanceKilometers: 5,
                    coordinates: coordinates
                )
            )
        ]
        XCTAssertEqual(ATHLTHArenaDraftValidation.issue(for: draft), .missingRoute)
    }

    func testLegacyPresetRoundsNeedNoCustomDistanceField() {
        var draft = validDraft()
        draft.rounds = [
            ATHLTHArenaRoundDraft(
                template: .fastest1K, title: "1 km", rules: "Fastest time"
            ),
            ATHLTHArenaRoundDraft(
                template: .fastest5K, title: "5 km", rules: "Fastest time"
            ),
            ATHLTHArenaRoundDraft(
                template: .mostDistance, title: "Most km", rules: "Highest total"
            )
        ]
        XCTAssertNil(ATHLTHArenaDraftValidation.issue(for: draft))
    }
}
