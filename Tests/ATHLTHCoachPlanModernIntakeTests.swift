import XCTest
@testable import ATHLTH

final class ATHLTHCoachPlanModernIntakeTests: XCTestCase {
    private func completeBase() -> ATHLTHAIProgramIntake {
        var intake = ATHLTHAIProgramIntake()
        intake.trainingTypes = [.running]
        intake.outcomes = [.betterFitness]
        intake.experience = .regular
        intake.durationWeeks = 8
        intake.sessionsPerWeek = 3
        intake.availableDays = [1, 3, 5]
        intake.sessionDurationMinutes = 45
        intake.locations = [.outdoors]
        intake.equipment = ["Bodyweight / no equipment"]
        // Explicit enum case: `.none` on the optional property means nil.
        intake.injuryStatus = ATHLTHAIProgramIntake.InjuryStatus.none
        return intake
    }

    func testNoInjuriesIsAnExplicitAnswerRatherThanMissingInput() {
        let intake = completeBase()
        XCTAssertEqual(intake.injuryStatus?.rawValue, "none")
        XCTAssertFalse(intake.validationIssues.contains("injuryStatus"))
        XCTAssertTrue(intake.isComplete, "Unexpected intake issues: \(intake.validationIssues)")
    }

    func testAnyWeekCountAndWorkoutMinutesWithinSupportedRange() {
        var intake = completeBase()
        intake.durationWeeks = 13
        intake.sessionDurationMinutes = 37
        XCTAssertTrue(intake.isComplete, "Unexpected intake issues: \(intake.validationIssues)")

        intake.durationWeeks = 0
        XCTAssertTrue(intake.validationIssues.contains("durationWeeks"))
        intake.durationWeeks = 53
        XCTAssertTrue(intake.validationIssues.contains("durationWeeks"))
        intake.durationWeeks = 13

        intake.sessionDurationMinutes = 9
        XCTAssertTrue(intake.validationIssues.contains("sessionDurationMinutes"))
        intake.sessionDurationMinutes = 181
        XCTAssertTrue(intake.validationIssues.contains("sessionDurationMinutes"))
    }

    func testTwoInjuriesKeepIndependentConditionsAndConsent() throws {
        var intake = completeBase()
        intake.injuryStatus = .considerations
        intake.injuries = [
            .init(area: "Knees", condition: .avoidLoading),
            .init(area: "Shoulders", condition: .trainLightly)
        ]
        intake.injuryNotes = "Some private details"
        XCTAssertTrue(intake.isComplete)
        XCTAssertNil(intake.sharedInjurySafetyNotes)
        XCTAssertFalse(intake.coachContext.contains("Knees"))
        XCTAssertFalse(intake.coachContext.contains("Shoulders"))
        XCTAssertFalse(intake.coachContext.contains("Some private details"))

        intake.healthSharingAuthorized = true
        XCTAssertTrue(intake.isComplete)
        let shared = try XCTUnwrap(intake.sharedInjurySafetyNotes)
        XCTAssertTrue(shared.contains("Knees"))
        XCTAssertTrue(shared.contains("Shoulders"))
        XCTAssertTrue(shared.contains("Do not prescribe loading"))
        XCTAssertTrue(shared.contains("Only gentle, low-load movements"))
        XCTAssertFalse(intake.coachContext.contains("Knees"))
        XCTAssertTrue(intake.avoidLowerBodyTraining)
    }

    func testIncompleteInjuryRowsAreRejectedInsteadOfBorrowingAnotherCondition() {
        var intake = completeBase()
        intake.injuryStatus = .considerations
        intake.injuries = [
            .init(area: "Knees", condition: .someLimitations),
            .init(area: "Shoulders", condition: nil)
        ]
        XCTAssertTrue(intake.validationIssues.contains("injuryEntries"))
        intake.injuries[1].condition = .trainLightly
        XCTAssertFalse(intake.validationIssues.contains("injuryEntries"))
        intake.injuries.removeFirst()
        XCTAssertEqual(intake.injuries.first?.area, "Shoulders")
        XCTAssertEqual(intake.injuries.first?.condition, .trainLightly)
        XCTAssertFalse(intake.avoidLowerBodyTraining)
    }

    func testLegacySingleInjuryRemainsSupported() throws {
        var intake = completeBase()
        intake.injuryStatus = .considerations
        intake.injuryAreas = ["Knees"]
        intake.injurySeverity = .moderate
        intake.injuryRestriction = .avoidAffectedArea
        intake.healthSharingAuthorized = true
        XCTAssertTrue(intake.isComplete)
        XCTAssertTrue(try XCTUnwrap(intake.sharedInjurySafetyNotes).contains("Knees"))
    }
    func testUnansweredInjuryAndNoEquipmentSelectionsAreOptional() {
        var intake = completeBase()
        intake.injuryStatus = nil
        intake.equipment = []
        XCTAssertTrue(intake.isComplete, "\(intake.validationIssues)")
        XCTAssertFalse(intake.validationIssues.contains("injuryStatus"))
        XCTAssertFalse(intake.validationIssues.contains("equipment"))
        XCTAssertTrue(intake.coachContext.contains("Injury status was not provided"))
        XCTAssertTrue(intake.coachContext.contains(
            "Assume all standard equipment is available"
        ))
        XCTAssertNil(intake.sharedInjurySafetyNotes)
    }

    func testCoachCanChooseFrequencyAndDurationWhenAthleteAllowsIt() {
        var intake = completeBase()
        intake.sessionsPerWeek = nil
        intake.sessionDurationMinutes = nil
        intake.coachChoosesFrequency = true
        intake.coachChoosesDuration = true
        XCTAssertTrue(intake.isComplete, "\(intake.validationIssues)")
        XCTAssertTrue(intake.coachContext.contains(
            "Coach chooses within available weekdays"
        ))
        XCTAssertTrue(intake.coachContext.contains(
            "Coach chooses 10–180 minutes"
        ))
        intake.coachChoosesFrequency = false
        XCTAssertTrue(intake.validationIssues.contains("sessionsPerWeek"))
        intake.coachChoosesDuration = false
        XCTAssertTrue(intake.validationIssues.contains("sessionDurationMinutes"))
    }

    func testCyclingAloneIsAValidCoachTrainingChoice() {
        var intake = completeBase()
        intake.trainingTypes = []
        intake.includesCycling = true
        XCTAssertEqual(intake.resolvedTrainingFocus, .generalFitness)
        XCTAssertFalse(intake.validationIssues.contains("trainingTypes"))
        XCTAssertTrue(intake.coachContext.contains("Cycling"))
    }

    func testUnavailableEquipmentIsIndependentOfAvailableEquipment() {
        var intake = completeBase()
        intake.equipment = []
        intake.unavailableEquipment = ["Treadmill", "Squat rack"]
        XCTAssertTrue(intake.isComplete, "\(intake.validationIssues)")
        XCTAssertTrue(intake.coachContext.contains(
            "Unavailable equipment (never prescribe): Squat rack, Treadmill"
        ))
        XCTAssertTrue(intake.coachContext.contains(
            "Assume all standard equipment is available except explicitly excluded"
        ))
    }

    func testStrongerOutcomeRequiresRealLiftAndWeight() {
        var intake = completeBase()
        intake.outcomes = [.stronger]
        XCTAssertTrue(intake.validationIssues.contains("targetExerciseName"))
        XCTAssertTrue(intake.validationIssues.contains("targetLiftKilograms"))
        intake.targetExerciseName = "Benkpress"
        intake.targetLiftKilograms = 100
        XCTAssertTrue(intake.isComplete, "\(intake.validationIssues)")
        XCTAssertTrue(intake.coachContext.contains("100 kg in Benkpress"))
    }

}
