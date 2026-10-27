import XCTest
@testable import ATHLTH

final class ATHLTHAIProgramIntakeTests: XCTestCase {
    func testFreshIntakeDoesNotChooseAnythingForAthlete() {
        let intake = ATHLTHAIProgramIntake()

        XCTAssertTrue(intake.trainingTypes.isEmpty)
        XCTAssertTrue(intake.outcomes.isEmpty)
        XCTAssertTrue(intake.muscleGroups.isEmpty)
        XCTAssertNil(intake.experience)
        XCTAssertNil(intake.durationWeeks)
        XCTAssertNil(intake.sessionsPerWeek)
        XCTAssertTrue(intake.availableDays.isEmpty)
        XCTAssertNil(intake.sessionDurationMinutes)
        XCTAssertTrue(intake.locations.isEmpty)
        XCTAssertNil(intake.outdoorSharePercent)
        XCTAssertTrue(intake.equipment.isEmpty)
        XCTAssertNil(intake.injuryStatus)
        XCTAssertFalse(intake.isComplete)
    }

    func testStrengthPlanRequiresExplicitMuscleFocus() {
        var intake = completeIntake()
        intake.trainingTypes = [.strength]
        intake.muscleGroups = []

        XCTAssertTrue(intake.validationIssues.contains("muscleGroups"))

        intake.muscleGroups = ["Full body"]
        XCTAssertFalse(intake.validationIssues.contains("muscleGroups"))
    }

    func testGymAndOutdoorSelectionRequiresExplicitBalance() {
        var intake = completeIntake()
        intake.locations = [.gym, .outdoors]
        intake.outdoorSharePercent = nil

        XCTAssertTrue(intake.validationIssues.contains("locationBalance"))

        intake.outdoorSharePercent = 70
        XCTAssertFalse(intake.validationIssues.contains("locationBalance"))
        XCTAssertTrue(intake.coachContext.contains("70% outdoors / 30% gym"))
    }

    func testSevereKneeRestrictionIsMandatoryInCoachContext() {
        var intake = completeIntake()
        intake.injuryStatus = .considerations
        intake.injuryAreas = ["Knees"]
        intake.injurySeverity = .severe
        intake.injuryRestriction = .avoidLowerBody
        intake.injuryNotes = "Knee is very painful."
        intake.healthSharingAuthorized = true

        XCTAssertTrue(intake.isComplete)
        XCTAssertTrue(intake.coachContext.contains("No lower-body training"))
        XCTAssertTrue(intake.coachContext.contains("do not prescribe running"))
        XCTAssertTrue(intake.coachContext.contains("Knees"))
    }

    func testInjuryDetailsCannotBeSentWithoutConsent() {
        var intake = completeIntake()
        intake.injuryStatus = .considerations
        intake.injuryAreas = ["Feet / ankles"]
        intake.injurySeverity = .moderate
        intake.injuryRestriction = .avoidAffectedArea
        intake.healthSharingAuthorized = false

        XCTAssertTrue(
            intake.validationIssues.contains("healthSharingAuthorized")
        )
        XCTAssertFalse(intake.isComplete)
    }

    private func completeIntake() -> ATHLTHAIProgramIntake {
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
        intake.injuryStatus = .none
        return intake
    }
}
