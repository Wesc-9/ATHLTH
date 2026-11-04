import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHGuidedPlanAutofillTests: XCTestCase {
    private func runningSession(_ title: String = "Rolig løp") -> AIProgramDraftSession {
        AIProgramDraftSession(
            title: title,
            kind: WorkoutKind.running.rawValue,
            durationMinutes: 30,
            targetDistanceKilometers: 5,
            targetPaceSecondsPerKilometer: nil,
            notes: nil,
            exercises: [],
            blocks: nil
        )
    }

    private func aiDraft(weeks: Int) -> AIProgramDraft {
        AIProgramDraft(
            title: "AI proposal",
            summary: "Review before using",
            weeks: (1...weeks).map { week in
                AIProgramDraftWeek(
                    weekNumber: week,
                    title: "Week \(week)",
                    days: (1...7).map { weekday in
                        AIProgramDraftDay(
                            dayIndex: weekday,
                            title: "Day \(weekday)",
                            sessions: weekday == 1 ? [runningSession()] : []
                        )
                    }
                )
            }
        )
    }

    func testFourWeekAutofillProducesFourWeeksAndLeavesOtherDaysAsRest() throws {
        let proposal = try ATHLTHGuidedPlanAutofill.propose(
            aiDraft(weeks: 4),
            existing: [:],
            protectedWeekdays: [],
            weekCount: 4,
            defaultSessionMinutes: 30
        )
        XCTAssertEqual(proposal.filledDays, 28)
        XCTAssertEqual(proposal.addedWorkouts, 4)
        XCTAssertEqual(proposal.restDays, 24)
        XCTAssertTrue(proposal.edits[1]?.detailedWorkout?.isValid == true)
        XCTAssertTrue(proposal.edits[8]?.detailedWorkout?.isValid == true)
        XCTAssertTrue(proposal.edits[22]?.detailedWorkout?.isValid == true)
        XCTAssertEqual(proposal.edits[28]?.isRestDay, true)
    }

    func testExistingSessionsAndRestDaysAreNeverOverwritten() throws {
        var custom = ATHLTHPlanWeekDayEdit()
        custom.title = "My own run"
        var rest = ATHLTHPlanWeekDayEdit()
        rest.isRestDay = true
        let initial = [1: custom, 2: rest]

        let proposal = try ATHLTHGuidedPlanAutofill.propose(
            aiDraft(weeks: 2),
            existing: initial,
            protectedWeekdays: [],
            weekCount: 2,
            defaultSessionMinutes: 30
        )
        XCTAssertEqual(proposal.edits[1], custom)
        XCTAssertEqual(proposal.edits[2], rest)
        XCTAssertEqual(proposal.addedWorkouts, 1)
        XCTAssertEqual(proposal.filledDays, 12)
        XCTAssertTrue(proposal.edits[8]?.detailedWorkout?.isValid == true)
    }

    func testExistingWeeklyBlueprintProtectsEveryCorrespondingWeekday() throws {
        let proposal = try ATHLTHGuidedPlanAutofill.propose(
            aiDraft(weeks: 2),
            existing: [:],
            protectedWeekdays: [1],
            weekCount: 2,
            defaultSessionMinutes: 30
        )
        XCTAssertNil(proposal.edits[1])
        XCTAssertNil(proposal.edits[8])
        XCTAssertEqual(proposal.addedWorkouts, 0)
        XCTAssertEqual(proposal.filledDays, 12)
    }

    func testIncompleteCoachResponseDoesNotPartiallyModifyPlan() {
        XCTAssertThrowsError(try ATHLTHGuidedPlanAutofill.propose(
            aiDraft(weeks: 1),
            existing: [:],
            protectedWeekdays: [],
            weekCount: 4,
            defaultSessionMinutes: 30
        ))
    }

    func testCopyAnyCompletedWeekOnlyIntoUnplannedDates() {
        var source = ATHLTHPlanWeekDayEdit()
        source.title = "Week two workout"
        var explicitRest = ATHLTHPlanWeekDayEdit()
        explicitRest.isRestDay = true
        var existing = ATHLTHPlanWeekDayEdit()
        existing.title = "Original week three workout"

        let initial = [8: source, 9: explicitRest, 15: existing]
        let copied = ATHLTHGuidedPlanAutofill.copy(
            from: 1,
            into: initial,
            numberOfWeeks: 2,
            totalWeeks: 4
        )
        XCTAssertEqual(copied[15], existing)
        XCTAssertEqual(copied[16], explicitRest)
        XCTAssertEqual(copied[22], source)
        XCTAssertEqual(copied[23], explicitRest)
        XCTAssertEqual(copied[8], source)
    }
}
