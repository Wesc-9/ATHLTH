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

    func testStrictApprovalRejectsUnavailableDayAndWeeklyOverload() {
        let draft = AIProgramDraft(
            title: "Busy draft",
            summary: "",
            weeks: [
                AIProgramDraftWeek(
                    weekNumber: 1,
                    title: "Week 1",
                    days: (1...7).map { day in
                        AIProgramDraftDay(
                            dayIndex: day,
                            title: "Day \(day)",
                            sessions: day <= 3 ? [workout()] : []
                        )
                    }
                )
            ]
        )
        let issues = ATHLTHPlanDraftValidator.issues(
            in: draft,
            expectedWeeks: 1,
            allowedDayIndexes: [1, 3, 5],
            maximumSessionsPerWeek: 2,
            requireFullWeeks: true
        )
        XCTAssertTrue(issues.contains("outside_available_days"))
        XCTAssertTrue(issues.contains("exceeds_weekly_session_limit"))
        XCTAssertFalse(issues.contains("incomplete_week_days"))
    }

    func testStrictApprovalPreservesLockedExistingDay() {
        let draft = AIProgramDraft(
            title: "Fill gaps only",
            summary: "",
            weeks: [
                AIProgramDraftWeek(
                    weekNumber: 1,
                    title: "Week 1",
                    days: (1...7).map { day in
                        AIProgramDraftDay(
                            dayIndex: day,
                            title: "Day \(day)",
                            sessions: day == 1 ? [workout()] : []
                        )
                    }
                )
            ]
        )
        let issues = ATHLTHPlanDraftValidator.issues(
            in: draft,
            expectedWeeks: 1,
            allowedDayIndexes: [1, 3, 5],
            maximumSessionsPerWeek: 3,
            lockedDayKeys: ["1:1"],
            requireFullWeeks: true
        )
        XCTAssertTrue(issues.contains("overwrites_existing_workout"))
    }

    func testStrictApprovalRejectsIncompleteWeekAndMultipleSessions() {
        let draft = AIProgramDraft(
            title: "Incomplete",
            summary: "",
            weeks: [
                AIProgramDraftWeek(
                    weekNumber: 1,
                    title: "Week 1",
                    days: [
                        AIProgramDraftDay(
                            dayIndex: 1,
                            title: "Monday",
                            sessions: [workout(), workout()]
                        )
                    ]
                )
            ]
        )
        let issues = ATHLTHPlanDraftValidator.issues(
            in: draft,
            expectedWeeks: 1,
            requireFullWeeks: true
        )
        XCTAssertTrue(issues.contains("incomplete_week_days"))
        XCTAssertTrue(issues.contains("multiple_sessions_on_day"))
    }

    func testStrictApprovalAcceptsCompleteWeekWithConstrainedSchedule() {
        let draft = AIProgramDraft(
            title: "Available days",
            summary: "",
            weeks: [
                AIProgramDraftWeek(
                    weekNumber: 1,
                    title: "Week 1",
                    days: (1...7).map { day in
                        AIProgramDraftDay(
                            dayIndex: day,
                            title: "Day \(day)",
                            sessions: [1, 3, 5].contains(day) ? [workout()] : []
                        )
                    }
                )
            ]
        )
        XCTAssertTrue(ATHLTHPlanDraftValidator.issues(
            in: draft,
            expectedWeeks: 1,
            allowedDayIndexes: [1, 3, 5],
            maximumSessionsPerWeek: 3,
            lockedDayKeys: ["1:2"],
            requireFullWeeks: true
        ).isEmpty)
    }

}
