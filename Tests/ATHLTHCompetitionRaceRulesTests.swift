import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCompetitionRaceRulesTests: XCTestCase {
    func testOneRaceDisciplineCanBeReusedForEachCompetitionFormat() {
        XCTAssertEqual(ATHLTHCompetitionDiscipline.allCases.count, 5)
        XCTAssertEqual(ATHLTHCompetitionSprintMode.allCases.count, 3)
        XCTAssertTrue(ATHLTHCompetitionRaceRules().isValid)
        XCTAssertTrue(ATHLTHCompetitionRaceRules().isOperational)
    }

    func testSprintStartAndWatchProvenanceFailClosedUntilMotorSupportsThem() {
        var race = ATHLTHCompetitionRaceRules()
        race.discipline = .sprint
        XCTAssertTrue(race.isOperational)
        race.sprintMode = .relay
        XCTAssertFalse(race.isOperational)
        race.sprintMode = .staggered
        XCTAssertFalse(race.isOperational)
        race.sprintMode = .massStart
        race.recordingDevice = .appleWatch
        XCTAssertFalse(race.isOperational)
        race.recordingDevice = .any
        race.sprintTarget = .route
        XCTAssertFalse(race.isValid)
        XCTAssertFalse(race.isOperational)
        race.routeID = UUID()
        race.routeName = "Felles løype"
        XCTAssertTrue(race.isValid)
        XCTAssertFalse(race.isOperational)
    }

    func testLapsDoNotNeedDistanceButRequireTheSameCourse() {
        var race = ATHLTHCompetitionRaceRules()
        race.discipline = .laps
        XCTAssertFalse(race.isValid)
        race.lapCourseName = "Tre runder rundt bygget"
        race.lapCount = 3
        race.lapVerification = .supervised
        XCTAssertTrue(race.isValid)
        XCTAssertTrue(race.isOperational)
        race.lapVerification = .gps
        XCTAssertFalse(race.isOperational)
        race.lapCount = 0
        XCTAssertFalse(race.isValid)
    }

    func testOldRaceRulesDecodeWithSafeDefaults() throws {
        let legacy = try JSONDecoder().decode(
            ATHLTHCompetitionRaceRules.self,
            from: Data("{}".utf8)
        )
        XCTAssertEqual(legacy.discipline, .workout)
        XCTAssertEqual(legacy.countdownSeconds, 10)
        XCTAssertEqual(legacy.recordingDevice, .any)
        XCTAssertEqual(legacy.lapVerification, .supervised)
        let roundTrip = try JSONDecoder().decode(
            ATHLTHCompetitionRaceRules.self,
            from: JSONEncoder().encode(legacy)
        )
        XCTAssertEqual(roundTrip, legacy)
    }

    func testSingleEventDraftDoesNotCreateFictionalMatches() throws {
        let participants = (0..<3).map {
            ATHLTHTournamentParticipant(id: UUID(), username: "Utøver \($0)")
        }
        let draft = ATHLTHTournamentDraft(
            ownerID: participants[0].id, clubID: nil,
            title: "Én sprint", format: .league,
            singleEventMode: true,
            groupSize: 4, qualifiersPerGroup: 2,
            participants: participants,
            allowedActivities: [.running]
        )
        XCTAssertTrue(try ATHLTHTournamentEngine.initialFixtures(
            for: draft).isEmpty)
        let restored = try JSONDecoder().decode(
            ATHLTHTournamentDraft.self,
            from: JSONEncoder().encode(draft)
        )
        XCTAssertTrue(restored.singleEventMode)
        XCTAssertEqual(restored.participants.count, 3)
    }
}
