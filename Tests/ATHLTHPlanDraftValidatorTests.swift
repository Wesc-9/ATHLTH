import XCTest
@testable import ATHLTH

final class ATHLTHPlanDraftValidatorTests: XCTestCase {
    private func workout(
        title: String = "Strength",
        duration: Int? = 50,
        sets: Int = 3
    ) -> AIProgramDraftSession {
        AIProgramDraftSession(
            title: title,
            kind: "strength",
            durationMinutes: duration,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            notes: nil,
            exercises: [
                AIProgramDraftExercise(
                    name: "Squat",
                    sets: sets,
                    reps: 8,
                    targetRPE: 7,
                    restSeconds: 90,
                    notes: nil
                )
            ]
        )
    }

    func testValidMultiweekDraftIsAcceptedWithoutModification() {
        let draft = AIProgramDraft(
            title: "Balanced training",
            summary: "Strength and running",
            weeks: (1...8).map { index in
                AIProgramDraftWeek(
                    weekNumber: index,
                    title: "Week \(index)",
                    days: [
                        AIProgramDraftDay(
                            dayIndex: 1,
                            title: "Monday",
                            sessions: [workout()]
                        )
                    ]
                )
            }
        )
        XCTAssertTrue(ATHLTHPlanDraftValidator.issues(
            in: draft, expectedWeeks: 8
        ).isEmpty)
        XCTAssertEqual(draft.sessionCount, 8)
    }

    func testIncompleteProgramIsNotApproachableForApproval() {
        let draft = AIProgramDraft(
            title: "Partial",
            summary: "",
            weeks: [
                AIProgramDraftWeek(
                    weekNumber: 1,
                    title: "",
                    days: [
                        AIProgramDraftDay(
                            dayIndex: 1,
                            title: "Monday",
                            sessions: [workout()]
                        )
                    ]
                )
            ]
        )
        XCTAssertTrue(ATHLTHPlanDraftValidator.issues(
            in: draft, expectedWeeks: 8
        ).contains("incomplete_program"))
    }

    func testInvalidWorkoutTargetsAreRejectedBeforePersistence() {
        let draft = AIProgramDraft(
            title: "Invalid plan",
            summary: "",
            weeks: [
                AIProgramDraftWeek(
                    weekNumber: 1,
                    title: "",
                    days: [
                        AIProgramDraftDay(
                            dayIndex: 9,
                            title: "Unknown",
                            sessions: [workout(title: "", duration: -4, sets: 0)]
                        )
                    ]
                )
            ]
        )
        let problems = ATHLTHPlanDraftValidator.issues(in: draft, expectedWeeks: 1)
        XCTAssertTrue(problems.contains("invalid_day_indices"))
        XCTAssertTrue(problems.contains("invalid_duration"))
        XCTAssertTrue(problems.contains("invalid_exercise"))
        XCTAssertTrue(problems.contains("missing_workout_title"))
    }
}
