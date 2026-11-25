import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCompetitionRaceRulesTests: XCTestCase {
    func testUnifiedDuelModeRoundTripsThroughSharedRaceRules() throws {
        var rules = ATHLTHCompetitionRaceRules()
        rules.duelMode = true
        rules.exerciseScoringVersion = 1
        rules.discipline = .workout
        let decoded = try JSONDecoder().decode(ATHLTHCompetitionRaceRules.self,
            from: JSONEncoder().encode(rules))
        XCTAssertEqual(decoded.duelMode, true)
        XCTAssertEqual(decoded.exerciseScoringVersion, 1)
        XCTAssertEqual(decoded.discipline, .workout)
        XCTAssertNil(ATHLTHCompetitionRaceRules().duelMode)
    }

    func testScoringRulesSurviveRoundTrip() throws {
        let exercise = UUID()
        let athlete = UUID()
        var rules = ATHLTHCompetitionRaceRules()
        rules.scoringMode = .target
        rules.pointsPerExercise = 3
        rules.scoringGoals = [ATHLTHCompetitionRaceRules.key(exercise): 1250]
        rules.exerciseWeights = [ATHLTHCompetitionRaceRules.key(exercise): 2]
        rules.handicapPercentages = [ATHLTHCompetitionRaceRules.key(athlete): 10]
        rules.reviewHours = 48
        let decoded = try JSONDecoder().decode(ATHLTHCompetitionRaceRules.self, from: JSONEncoder().encode(rules))
        XCTAssertEqual(decoded.effectiveScoringMode, .target)
        XCTAssertEqual(decoded.goal(for: exercise), 1250)
        XCTAssertEqual(decoded.weight(for: exercise), 2)
        XCTAssertEqual(decoded.handicap(for: athlete), 10)
        XCTAssertEqual(decoded.reviewHours, 48)
        XCTAssertTrue(decoded.isValid)
        rules.handicapPercentages = [ATHLTHCompetitionRaceRules.key(athlete): 31]
        XCTAssertFalse(rules.isValid)
    }

    func testPreviewPointsUsesServerMetricDirectionAndSharedRanks() {
        let score = ATHLTHCompetitionRaceRules.previewPoints
        XCTAssertEqual(score(.ranking, "distance", [100, 110], [0, 10], 2, 3, nil), [6, 12])
        XCTAssertEqual(score(.ranking, "duration", [100, 100, 80], [0, 0, 0], 1, 1, nil), [3, 3, 1])
        XCTAssertEqual(score(.winner, "repetitions", [10, 10], [0, 0], 2, 1, nil), [2, 2])
        XCTAssertEqual(score(.target, "distance", [100, 110], [0, 10], 1, 1, 100), [1, 1])
        XCTAssertEqual(score(.target, "time", [45, 50], [0, 10], 2, 1, 50), [0, 2])
        XCTAssertEqual(score(.closest, "duration", [90, 110], [0, 0], 1, 2, 100), [2, 2])
        XCTAssertEqual(score(.completion, "repetitions", [8, 12], [0, 0], 3, 2, nil), [6, 6])
        XCTAssertNil(score(.target, "distance", [100, 110], [0, 10], 1, 1, nil))
        XCTAssertNil(score(.ranking, "distance", [100, 110], [0, 31], 1, 1, nil))
        XCTAssertNil(score(.winner, "invalid", [100], [0], 1, 1, nil))
    }

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
