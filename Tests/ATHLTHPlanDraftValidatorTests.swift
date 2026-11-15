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


    func testCoachStrengthProducesExecutableSetAndRestBlocks() {
        let session = workout().makePlannedSession()
        let blocks = session.resolvedWorkoutBlocks
        XCTAssertEqual(blocks.filter { $0.kind == .exercise }.count, 3)
        XCTAssertEqual(blocks.filter { $0.kind == .rest }.count, 2)
        XCTAssertTrue(session.exercises.isEmpty,
                      "A unified timeline must not execute exercises twice")
        XCTAssertEqual(blocks.first(where: { $0.kind == .exercise })?
            .targetEffortRPE, 7)
        XCTAssertEqual(blocks.first(where: { $0.kind == .exercise })?
            .repetitions, 8)
    }

    func testCoachSteadyRunCreatesRunnableATHLTHBlock() {
        let draft = AIProgramDraftSession(
            title: "Easy Aerobic Run", kind: "running",
            durationMinutes: 45, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            notes: nil, exercises: []
        )
        let workout = draft.makePlannedSession()
        XCTAssertEqual(workout.kind, .running)
        XCTAssertEqual(workout.resolvedWorkoutBlocks.count, 1)
        XCTAssertEqual(workout.resolvedWorkoutBlocks.first?.kind, .run)
        XCTAssertEqual(workout.resolvedWorkoutBlocks.first?.durationSeconds, 2700)
    }

    func testCoachRejectsStrengthWithoutSetsAndIntervalsWithoutDrags() {
        let unstructuredStrength = AIProgramDraftSession(
            title: "Full Body Strength", kind: "strength",
            durationMinutes: 60, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            notes: nil, exercises: []
        )
        let unstructuredInterval = AIProgramDraftSession(
            title: "4x4 Interval Run", kind: "running",
            durationMinutes: 45, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            notes: nil, exercises: []
        )
        let draft = AIProgramDraft(
            title: "ATHLTH Coach", summary: "",
            weeks: [AIProgramDraftWeek(
                weekNumber: 1, title: "Week 1",
                days: [AIProgramDraftDay(
                    dayIndex: 1, title: "Monday",
                    sessions: [unstructuredStrength, unstructuredInterval]
                )]
            )]
        )
        let issues = ATHLTHPlanDraftValidator.issues(
            in: draft, expectedWeeks: 1,
            requireExecutableWorkouts: true
        )
        XCTAssertTrue(issues.contains("strength_missing_structured_sets"))
        XCTAssertTrue(issues.contains("interval_missing_drags"))
    }

    func testCoachAcceptsStructuredStrengthAndSteadyRun() {
        let easyRun = AIProgramDraftSession(
            title: "Easy Aerobic Run", kind: "running",
            durationMinutes: 40, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            notes: nil, exercises: []
        )
        let draft = AIProgramDraft(
            title: "ATHLTH Coach", summary: "",
            weeks: [AIProgramDraftWeek(
                weekNumber: 1, title: "Week 1",
                days: [
                    AIProgramDraftDay(dayIndex: 1, title: "Monday",
                                      sessions: [workout()]),
                    AIProgramDraftDay(dayIndex: 3, title: "Wednesday",
                                      sessions: [easyRun])
                ]
            )]
        )
        XCTAssertTrue(ATHLTHPlanDraftValidator.issues(
            in: draft, expectedWeeks: 1,
            requireExecutableWorkouts: true
        ).isEmpty)
    }

}
