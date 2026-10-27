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

    func testSevereKneeRestrictionIsDeliveredInDedicatedConsentField() throws {
        var intake = completeIntake()
        intake.injuryStatus = .considerations
        intake.injuryAreas = ["Knees"]
        intake.injurySeverity = .severe
        intake.injuryRestriction = .avoidLowerBody
        intake.injuryNotes = "Knee is very painful."
        intake.healthSharingAuthorized = true

        XCTAssertTrue(intake.isComplete)
        let shared = try XCTUnwrap(intake.sharedInjurySafetyNotes)
        XCTAssertTrue(shared.contains("No lower-body training"))
        XCTAssertTrue(shared.contains("Knees"))
        XCTAssertTrue(shared.contains("Knee is very painful"))
        XCTAssertFalse(intake.coachContext.contains("Knee is very painful"))
        XCTAssertFalse(intake.coachContext.contains("Knees"))
    }

    func testInjuryDetailsCannotBeSentWithoutConsent() {
        var intake = completeIntake()
        intake.injuryStatus = .considerations
        intake.injuryAreas = ["Feet / ankles"]
        intake.injurySeverity = .moderate
        intake.injuryRestriction = .avoidAffectedArea
        intake.healthSharingAuthorized = false

        XCTAssertFalse(
            intake.validationIssues.contains("healthSharingAuthorized")
        )
        XCTAssertTrue(intake.isComplete)
        XCTAssertFalse(intake.coachContext.contains("Feet / ankles"))
        XCTAssertFalse(intake.coachContext.contains("Knees"))
        XCTAssertTrue(intake.coachContext.contains("not authorized sharing"))
        XCTAssertNil(intake.sharedInjurySafetyNotes)
    }

    func testOptOutDoesNotRequireAdditionalInjuryFields() {
        var intake = completeIntake()
        intake.injuryStatus = .considerations
        intake.injuryAreas = []
        intake.injurySeverity = nil
        intake.injuryRestriction = nil
        intake.healthSharingAuthorized = false
        XCTAssertTrue(intake.isComplete)
        intake.healthSharingAuthorized = true
        XCTAssertTrue(intake.validationIssues.contains("injuryAreas"))
    }

    func testExplicitlyForbiddenExerciseNamesReachConsentedSafetyField() throws {
        var intake = completeIntake()
        intake.injuryStatus = .considerations
        intake.injuryAreas = ["Knees"]
        intake.injurySeverity = .moderate
        intake.injuryRestriction = .avoidAffectedArea
        intake.injuryNotes = "No impact at all; painful knee."
        intake.excludedMovements = "Knebøy\nLøping, hopping"
        intake.healthSharingAuthorized = true

        let shared = try XCTUnwrap(intake.sharedInjurySafetyNotes)
        XCTAssertTrue(shared.contains("No impact at all"))
        XCTAssertTrue(shared.contains("Knebøy"))
        XCTAssertTrue(shared.contains("Løping"))
        XCTAssertTrue(shared.contains("hopping"))
        XCTAssertFalse(intake.coachContext.contains("No impact at all"))

        intake.healthSharingAuthorized = false
        XCTAssertNil(intake.sharedInjurySafetyNotes)
        XCTAssertFalse(intake.coachContext.contains("Knebøy"))
    }

    func testForbiddenKneeExercisesAndEnglishSynonymsAreRejectedLocally() {
        let squat = AIProgramDraftExercise(
            name: "Barbell squats", sets: 3, reps: 8, targetRPE: nil,
            restSeconds: 90, notes: nil
        )
        let session = AIProgramDraftSession(
            title: "Strength", kind: "strength", durationMinutes: 40,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            notes: nil, exercises: [squat]
        )
        let draft = AIProgramDraft(
            title: "Test", summary: "", weeks: [
                AIProgramDraftWeek(
                    weekNumber: 1, title: "Week 1", days: [
                        AIProgramDraftDay(
                            dayIndex: 1, title: "Monday", sessions: [session]
                        )
                    ]
                )
            ]
        )
        let forbidden = ATHLTHAIInjurySafetyValidator.violations(
            in: draft, excludedMovements: ["Knebøy"], avoidLowerBody: false
        )
        XCTAssertEqual(forbidden, ["Barbell squats"])
        XCTAssertTrue(ATHLTHAIInjurySafetyValidator.violations(
            in: draft, excludedMovements: [], avoidLowerBody: true
        ).contains("Barbell squats"))
    }

    func testRunningPlanIsRejectedWhenLowerBodyLoadingIsForbidden() {
        let session = AIProgramDraftSession(
            title: "Intervals", kind: "running", durationMinutes: 45,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            notes: nil, exercises: []
        )
        let draft = AIProgramDraft(
            title: "Test", summary: "", weeks: [
                AIProgramDraftWeek(
                    weekNumber: 1, title: "Week 1", days: [
                        AIProgramDraftDay(
                            dayIndex: 1, title: "Monday", sessions: [session]
                        )
                    ]
                )
            ]
        )
        XCTAssertTrue(ATHLTHAIInjurySafetyValidator.violations(
            in: draft, excludedMovements: [], avoidLowerBody: true
        ).contains("running"))
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
