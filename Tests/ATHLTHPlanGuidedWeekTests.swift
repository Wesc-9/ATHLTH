import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlanGuidedWeekTests: XCTestCase {
    private func workout(_ title: String) -> ATHLTHPlanStructuredWorkoutBlueprint {
        let block = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Squat",
            exerciseSlug: nil, distanceMeters: nil, repetitions: 8,
            durationSeconds: nil, targetWeightKilograms: 40,
            loadNote: nil, notes: nil
        )
        return ATHLTHPlanStructuredWorkoutBlueprint(
            title: title, kind: .strength, durationMinutes: 45,
            routeID: nil, blocks: [block]
        )
    }

    private func makeWeeks() -> [TrainingPlanWeek] {
        (1...3).map { number in
            TrainingPlanWeek(
                id: UUID(), weekNumber: number, title: "Week \(number)",
                days: (1...7).map { day in
                    TrainingPlanDay(id: UUID(), dayIndex: day,
                                    title: "Day \(day)", sessions: [])
                }
            )
        }
    }

    func testCopyRetainsTwoWorkoutsRestDaysAndIndependentIDs() throws {
        let start = try XCTUnwrap(Calendar.current.date(
            from: DateComponents(year: 2026, month: 10, day: 17)
        ))
        let first = workout("Overkropp")
        var day = ATHLTHPlanWeekDayEdit(
            kind: .strength, title: "Overkropp", durationMinutes: 45,
            detailedWorkout: first
        )
        day.additionalDetailedWorkouts = [workout("Løping")]
        var rest = ATHLTHPlanWeekDayEdit()
        rest.isRestDay = true

        // 17 October is Saturday. Date-based weekday 6 maps to week dayIndex 1.
        var weeks = makeWeeks()
        ATHLTHPlanWeekDayEdit.apply(
            [6: day, 7: rest, 13: day],
            to: &weeks, startDate: start
        )
        XCTAssertEqual(weeks[0].days[0].sessions.map(\.title),
                       ["Overkropp", "Løping"])
        XCTAssertTrue(weeks[0].days[1].sessions.isEmpty)
        XCTAssertEqual(weeks[1].days[0].sessions.map(\.title),
                       ["Overkropp", "Løping"])
        XCTAssertNotEqual(weeks[0].days[0].sessions[0].id,
                          weeks[1].days[0].sessions[0].id)
        XCTAssertTrue(weeks[2].days[0].sessions.isEmpty)
    }

    func testPreviouslyPersistedEditCanDecodeWithOptionalNewFields() throws {
        let legacy = ATHLTHPlanWeekDayEdit(
            kind: .strength, title: "Legacy", durationMinutes: 40,
            detailedWorkout: workout("Legacy")
        )
        let data = try JSONEncoder().encode(legacy)
        let result = try JSONDecoder().decode(ATHLTHPlanWeekDayEdit.self, from: data)
        XCTAssertNil(result.isRestDay)
        XCTAssertNil(result.additionalDetailedWorkouts)
        XCTAssertEqual(result.detailedWorkout?.title, "Legacy")
    }
}
