import XCTest
@testable import ATHLTH

final class ATHLTHPlanDraftEditingTests: XCTestCase {
    private func makeDraft() -> AIProgramDraft {
        AIProgramDraft(
            title: "Strength and running",
            summary: "Test plan",
            weeks: (1...3).map { week in
                AIProgramDraftWeek(
                    weekNumber: week,
                    title: "Week \(week)",
                    days: [
                        AIProgramDraftDay(
                            dayIndex: 1,
                            title: "Monday",
                            sessions: [
                                AIProgramDraftSession(
                                    title: "Gym \(week)",
                                    kind: "strength",
                                    durationMinutes: 45,
                                    targetDistanceKilometers: nil,
                                    targetPaceSecondsPerKilometer: nil,
                                    notes: nil,
                                    exercises: [
                                        AIProgramDraftExercise(
                                            name: "Row",
                                            sets: 3,
                                            reps: 10,
                                            targetRPE: 7,
                                            restSeconds: 90,
                                            notes: nil
                                        )
                                    ]
                                )
                            ]
                        )
                    ]
                )
            }
        )
    }

    func testUpdatingOneProposedWorkoutLeavesOtherWeeksUntouched() throws {
        let before = makeDraft()
        let selection = ATHLTHPlanDraftWorkoutSelection(
            weekNumber: 2, dayIndex: 1, sessionIndex: 0
        )
        let original = try XCTUnwrap(ATHLTHPlanDraftEditing.workout(
            in: before, selection: selection
        ))
        let edited = AIProgramDraftSession(
            title: "Customized gym",
            kind: original.kind,
            durationMinutes: 35,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            notes: "Prioritize form",
            exercises: original.exercises
        )
        let after = try XCTUnwrap(ATHLTHPlanDraftEditing.replacing(
            in: before, selection: selection, with: edited
        ))
        XCTAssertEqual(before.weeks[1].days[0].sessions[0].title, "Gym 2")
        XCTAssertEqual(after.weeks[1].days[0].sessions[0].title, "Customized gym")
        XCTAssertEqual(after.weeks[1].days[0].sessions[0].durationMinutes, 35)
        XCTAssertEqual(before.weeks[0], after.weeks[0])
        XCTAssertEqual(before.weeks[2], after.weeks[2])
        XCTAssertTrue(ATHLTHPlanDraftValidator.issues(in: after, expectedWeeks: 3).isEmpty)
    }

    func testOutOfRangeEditorSelectionDoesNotMutate() {
        let draft = makeDraft()
        let missing = ATHLTHPlanDraftWorkoutSelection(
            weekNumber: 2, dayIndex: 7, sessionIndex: 999
        )
        XCTAssertNil(ATHLTHPlanDraftEditing.workout(in: draft, selection: missing))
        XCTAssertNil(ATHLTHPlanDraftEditing.replacing(
            in: draft,
            selection: missing,
            with: draft.weeks[0].days[0].sessions[0]
        ))
    }

    func testMovingDraftWorkoutDoesNotAffectOtherWeeksOrSaveThePlan() throws {
        let initial = makeDraft()
        let expanded = AIProgramDraft(
            title: initial.title,
            summary: initial.summary,
            weeks: initial.weeks.map { week in
                AIProgramDraftWeek(
                    weekNumber: week.weekNumber,
                    title: week.title,
                    days: week.days + [
                        AIProgramDraftDay(dayIndex: 2, title: "Tuesday", sessions: [])
                    ]
                )
            }
        )
        let selection = ATHLTHPlanDraftWorkoutSelection(
            weekNumber: 2, dayIndex: 1, sessionIndex: 0
        )
        let moved = try XCTUnwrap(ATHLTHPlanDraftEditing.moving(
            in: expanded, selection: selection, toDayIndex: 2
        ))
        XCTAssertEqual(expanded.weeks[1].days[0].sessions.count, 1)
        XCTAssertTrue(moved.weeks[1].days[0].sessions.isEmpty)
        XCTAssertEqual(moved.weeks[1].days[1].sessions.first?.title, "Gym 2")
        XCTAssertEqual(moved.weeks[0], expanded.weeks[0])
        XCTAssertEqual(moved.weeks[2], expanded.weeks[2])
        XCTAssertEqual(moved.sessionCount, expanded.sessionCount)
        XCTAssertTrue(ATHLTHPlanDraftValidator.issues(
            in: moved, expectedWeeks: 3
        ).isEmpty)
    }

    func testMoveRejectsAnOccupiedOrInvalidDestination() {
        let before = makeDraft()
        let selected = ATHLTHPlanDraftWorkoutSelection(
            weekNumber: 1, dayIndex: 1, sessionIndex: 0
        )
        XCTAssertNil(ATHLTHPlanDraftEditing.moving(
            in: before, selection: selected, toDayIndex: 1
        ))
        XCTAssertNil(ATHLTHPlanDraftEditing.moving(
            in: before, selection: selected, toDayIndex: 12
        ))
        let occupied = AIProgramDraft(
            title: before.title,
            summary: before.summary,
            weeks: before.weeks.map { week in
                AIProgramDraftWeek(
                    weekNumber: week.weekNumber,
                    title: week.title,
                    days: week.days + [
                        AIProgramDraftDay(
                            dayIndex: 2,
                            title: "Tuesday",
                            sessions: week.days[0].sessions
                        )
                    ]
                )
            }
        )
        XCTAssertNil(ATHLTHPlanDraftEditing.moving(
            in: occupied, selection: selected, toDayIndex: 2
        ))
    }


    func testMoveRespectsUserAvailableDays() {
        let draft = makeDraft()
        let week = draft.weeks[0]
        let editable = AIProgramDraft(
            title: draft.title,
            summary: draft.summary,
            weeks: [
                AIProgramDraftWeek(
                    weekNumber: week.weekNumber,
                    title: week.title,
                    days: week.days + [
                        AIProgramDraftDay(dayIndex: 2, title: "Tuesday", sessions: [])
                    ]
                )
            ]
        )
        let selection = ATHLTHPlanDraftWorkoutSelection(
            weekNumber: 1, dayIndex: 1, sessionIndex: 0
        )
        XCTAssertNil(ATHLTHPlanDraftEditing.moving(
            in: editable,
            selection: selection,
            toDayIndex: 2,
            allowedDayIndexes: [1, 3, 5]
        ))
        XCTAssertNotNil(ATHLTHPlanDraftEditing.moving(
            in: editable,
            selection: selection,
            toDayIndex: 2,
            allowedDayIndexes: [1, 2, 3]
        ))
    }

}
