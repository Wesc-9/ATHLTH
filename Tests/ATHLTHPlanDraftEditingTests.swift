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
}
