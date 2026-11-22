import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTournamentCompetitionSettingsTests: XCTestCase {
    private func participants() -> [ATHLTHTournamentParticipant] {
        [
            ATHLTHTournamentParticipant(id: UUID(), username: "Coach"),
            ATHLTHTournamentParticipant(id: UUID(), username: "Runner"),
            ATHLTHTournamentParticipant(id: UUID(), username: "Walker")
        ]
    }

    func testEveryIntervalUnitAndEveryoneFinishedAreAvailable() {
        XCTAssertEqual(
            Set(ATHLTHCompetitionIntervalUnit.allCases),
            Set([.minute, .hour, .day, .month])
        )
        XCTAssertEqual(
            Set(ATHLTHCompetitionUnlock.allCases),
            Set([.interval, .everyoneFinished])
        )
        XCTAssertEqual(ATHLTHTournamentCompetitionSettings().missedExercisePoints, 0)
    }

    func testInvalidStartDateCannotBePublished() {
        var options = ATHLTHTournamentCompetitionSettings()
        options.startsAt = Date().addingTimeInterval(-86_400)
        XCTAssertFalse(options.isValid)
        options.startsAt = Date().addingTimeInterval(60 * 86_400)
        XCTAssertTrue(options.isValid)
        options.startsAt = Date().addingTimeInterval(400 * 86_400)
        XCTAssertFalse(options.isValid)
    }

    func testClockAndCalendarIntervalBounds() {
        var options = ATHLTHTournamentCompetitionSettings()
        options.unit = .month
        options.every = 12
        XCTAssertTrue(options.isValid)
        options.every = 13
        XCTAssertFalse(options.isValid)
        options.unit = .minute
        options.every = 15
        XCTAssertTrue(options.isValid)
        options.unit = .hour
        options.every = 721
        XCTAssertFalse(options.isValid)
    }

    func testOnlySupportedExerciseDeadlinePresetsAreAccepted() {
        var options = ATHLTHTournamentCompetitionSettings()
        for hours in ATHLTHTournamentCadence.completionHours {
            options.completionHours = hours
            XCTAssertTrue(options.isValid)
        }
        options.completionHours = 0
        XCTAssertFalse(options.isValid)
        options.completionHours = 721
        XCTAssertFalse(options.isValid)
    }

    func testAllApprovalTypesAndVoluntaryRewardsRoundTripThroughDrafts() throws {
        var options = ATHLTHTournamentCompetitionSettings()
        options.startsAt = Date().addingTimeInterval(6 * 86_400)
        options.unlock = .everyoneFinished
        options.invitationPermission = .participants
        options.joinApproval = .participants
        options.agreement.allowed = "Only completed verified workouts"
        options.agreement.prohibited = "No false activity data"
        options.agreement.firstPrize = "Coffee"
        options.agreement.secondPrize = "Medal"
        options.agreement.thirdPrize = "Trophy"
        options.agreement.loserConsequence = "Volunteer to choose the next playlist"

        let roster = participants()
        let draft = ATHLTHTournamentDraft(
            ownerID: roster[0].id,
            clubID: nil,
            title: "Autumn Championship",
            format: .groups,
            groupSize: 4,
            qualifiersPerGroup: 2,
            participants: roster,
            allowedActivities: [.running, .walking, .strength],
            competitionSettings: options
        )
        let restored = try JSONDecoder().decode(
            ATHLTHTournamentDraft.self,
            from: JSONEncoder().encode(draft)
        )
        XCTAssertEqual(restored.competitionSettings, options)
        XCTAssertTrue(restored.competitionSettings.requiresExplicitConsent)
        XCTAssertEqual(restored.competitionSettings.joinApproval, .participants)
        XCTAssertEqual(restored.competitionSettings.unlock, .everyoneFinished)
        XCTAssertNil(restored.seasonID)
    }

    func testOldTournamentDraftsDefaultToSafePermissionRules() throws {
        let roster = participants()
        let draft = ATHLTHTournamentDraft(
            ownerID: roster[0].id, clubID: nil,
            title: "Legacy league", format: .league,
            groupSize: 4, qualifiersPerGroup: 2, participants: roster
        )
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(draft))
                as? [String: Any]
        )
        payload.removeValue(forKey: "competitionSettings")
        let data = try JSONSerialization.data(withJSONObject: payload)
        let old = try JSONDecoder().decode(
            ATHLTHTournamentDraft.self, from: data
        )
        XCTAssertEqual(old.competitionSettings.invitationPermission, .admin)
        XCTAssertEqual(old.competitionSettings.joinApproval, .admin)
        XCTAssertNil(old.competitionSettings.startsAt)
        XCTAssertEqual(old.competitionSettings.unlock, .interval)
        XCTAssertFalse(old.competitionSettings.requiresExplicitConsent)
    }

    func testNewStartModesAndMeetingCoordinates() {
        var settings = ATHLTHTournamentCompetitionSettings()
        settings.startMode = .scheduled
        XCTAssertFalse(settings.isValid)
        settings.startsAt = Date().addingTimeInterval(86_400)
        XCTAssertTrue(settings.isValid)
        settings.environment = .outdoor
        settings.meetingPlace = "Stadionporten"
        settings.meetingLat = 63.4297
        settings.meetingLon = 10.3933
        XCTAssertTrue(settings.isValid)
        settings.meetingLon = 181
        XCTAssertFalse(settings.isValid)
        settings.meetingLon = 10.3933
        settings.meetingPlace = String(repeating: "A", count: 241)
        XCTAssertFalse(settings.isValid)
    }

    func testCoachExerciseProposalMustHaveUniqueCatalogIDs() {
        var settings = ATHLTHTournamentCompetitionSettings()
        let id = UUID()
        settings.coachExerciseIDs = [id, id]
        XCTAssertFalse(settings.isValid)
        settings.coachExerciseIDs = [id, UUID()]
        XCTAssertTrue(settings.isValid)
        settings.coachExerciseIDs = (0..<13).map { _ in UUID() }
        XCTAssertFalse(settings.isValid)
    }

    func testPreviousDraftSettingsDecodeWithSafeDefaults() throws {
        let json = Data(#"""
        {
            "unlock":"interval",
            "every":7,
            "unit":"day",
            "completionHours":48,
            "invitationPermission":"admin",
            "joinApproval":"admin",
            "agreement": {
                "allowed":"","prohibited":"","firstPrize":"",
                "secondPrize":"","thirdPrize":"","loserConsequence":""
            }
        }
        """#.utf8)
        let old = try JSONDecoder().decode(
            ATHLTHTournamentCompetitionSettings.self, from: json
        )
        XCTAssertEqual(old.startMode, .manual)
        XCTAssertEqual(old.environment, .any)
        XCTAssertTrue(old.coachExerciseIDs.isEmpty)
        XCTAssertNil(old.meetingLat)
        XCTAssertNil(old.startsAt)
    }

    func testRulesCannotExceedBackendLengthBound() {
        var options = ATHLTHTournamentCompetitionSettings()
        options.agreement.firstPrize = String(repeating: "A", count: 501)
        XCTAssertFalse(options.isValid)
        options.agreement.firstPrize = String(repeating: "A", count: 500)
        XCTAssertTrue(options.isValid)
    }
}
