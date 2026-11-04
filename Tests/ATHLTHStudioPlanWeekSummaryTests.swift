import XCTest
@testable import ATHLTH

final class ATHLTHStudioPlanWeekSummaryTests: XCTestCase {
    private func workout(
        title: String = "Session",
        kind: WorkoutKind = .running,
        minutes: Int? = 40,
        restDay: Bool = false
    ) -> PlannedSession {
        var result = PlannedSession(
            id: UUID(),
            title: title,
            kind: kind,
            scheduledStart: nil,
            durationMinutes: minutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
        result.workoutCategory = restDay ? "rest_day" : nil
        return result
    }

    func testSummaryExcludesRestDaysAndUnknownDuration() {
        let days: [TrainingPlanDay] = [
            TrainingPlanDay(id: UUID(), dayIndex: 1, title: "", sessions: [
                workout(kind: .running, minutes: 50)
            ]),
            TrainingPlanDay(id: UUID(), dayIndex: 2, title: "", sessions: [
                workout(kind: .strength, minutes: nil)
            ]),
            TrainingPlanDay(id: UUID(), dayIndex: 3, title: "", sessions: [
                workout(kind: .recovery, minutes: nil, restDay: true)
            ]),
            TrainingPlanDay(id: UUID(), dayIndex: 4, title: "", sessions: [])
        ]
        let week = TrainingPlanWeek(
            id: UUID(), weekNumber: 1, title: "", days: days
        )
        let result = ATHLTHStudioPlanWeekSummary.calculate(week)
        XCTAssertEqual(result.workouts, 2)
        XCTAssertEqual(result.restDays, 2)
        XCTAssertEqual(result.knownMinutes, 50)
        XCTAssertEqual(result.missingDurationCount, 1)
        XCTAssertEqual(result.running, 1)
        XCTAssertEqual(result.strength, 1)
        XCTAssertEqual(result.other, 0)
    }

    func testPlanDaysFollowCalendarDaysAcrossDst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 24
        )))
        let day = TrainingPlanDay(
            id: UUID(), dayIndex: 2, title: "", sessions: []
        )
        let resolved = try XCTUnwrap(ATHLTHStudioPlanWeekSummary.date(
            for: day, inWeekIndex: 0, planStart: start, calendar: calendar
        ))
        XCTAssertEqual(calendar.component(.day, from: resolved), 25)
        XCTAssertNotEqual(
            resolved.timeIntervalSince(start),
            24 * 3600,
            "Calendar math must respect Oslo's daylight saving change."
        )
    }

    func testUnknownStartDateCannotInventCalendarDate() {
        let day = TrainingPlanDay(
            id: UUID(), dayIndex: 5, title: "", sessions: []
        )
        XCTAssertNil(ATHLTHStudioPlanWeekSummary.date(
            for: day, inWeekIndex: 3, planStart: nil
        ))
    }
}
