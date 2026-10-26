import XCTest
@testable import ATHLTH

final class TrainingPlanWeekEditorTests: XCTestCase {
    func testNewPerDayPreferencesRoundTripWithoutMigration() throws {
        let profile = TrainingPlanBuilderProfile(
            mode: .advanced,
            primaryFocus: .hybrid,
            goal: .improveFitness,
            sessionsPerWeek: 2,
            preferredDayIndexes: [1, 4],
            preferredWorkoutKindsByDay: [1: .strength, 4: .running],
            preferredWorkoutTitlesByDay: [1: "Overkropp", 4: "Bakkeintervaller"],
            preferredWorkoutMinutesByDay: [1: 55, 4: 35]
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(TrainingPlanBuilderProfile.self, from: data)
        XCTAssertEqual(decoded.preferredWorkoutKindsByDay?[1], .strength)
        XCTAssertEqual(decoded.preferredWorkoutTitlesByDay?[4], "Bakkeintervaller")
        XCTAssertEqual(decoded.preferredWorkoutMinutesByDay?[1], 55)
        XCTAssertEqual(decoded.preferredDayIndexes, [1, 4])
    }

    func testLegacyProfileDecodesWithoutNewSessionFields() throws {
        let original = TrainingPlanBuilderProfile(
            mode: .advanced,
            primaryFocus: .running,
            goal: .improveFitness,
            sessionsPerWeek: 3,
            preferredDayIndexes: [1, 3, 5]
        )
        let raw = try JSONEncoder().encode(original)
        let updated = try JSONDecoder().decode(TrainingPlanBuilderProfile.self, from: raw)
        XCTAssertNil(updated.preferredWorkoutTitlesByDay)
        XCTAssertNil(updated.preferredWorkoutMinutesByDay)
    }

    func testAdvancedPlanJourneyUsesGoalAndBuildMethodInsteadOfLegacyProfile() {
        let stages = ATHLTHPlanJourney.sequence(advanced: true)
        XCTAssertEqual(stages, [.mode, .goal, .basics, .approach, .week, .review])
        XCTAssertFalse(stages.contains(.profile))
        XCTAssertEqual(
            ATHLTHPlanJourney.previous(before: .week, advanced: true), .approach
        )
        XCTAssertEqual(
            ATHLTHPlanJourney.restoredStep("profile", advanced: true), .approach
        )
        XCTAssertEqual(ATHLTHPlanJourney.displayedCount(advanced: true), 5)
    }
}
