import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainingPlanScheduleTests: XCTestCase {
    func testProgramStartingThursdayShowsFirstDayOnThursday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let thursday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 15
        )))
        let monday = try XCTUnwrap(calendar.date(byAdding: .day, value: 4, to: thursday))
        let first = workout("Strength", kind: .strength)
        let fifth = workout("Walk", kind: .walking)
        let plan = plan(start: thursday, weeks: [TrainingPlanWeek(
            id: UUID(), weekNumber: 1, title: "Week 1",
            days: [
                TrainingPlanDay(id: UUID(), dayIndex: 1, title: "", sessions: [first]),
                TrainingPlanDay(id: UUID(), dayIndex: 5, title: "", sessions: [fifth])
            ]
        )])

        XCTAssertEqual(
            ATHLTHTrainingPlanSchedule.sessions(in: plan, on: thursday, calendar: calendar).map(\.id),
            [first.id]
        )
        XCTAssertEqual(
            ATHLTHTrainingPlanSchedule.sessions(in: plan, on: monday, calendar: calendar).map(\.id),
            [fifth.id]
        )
    }

    func testPlanDoesNotRepeatLastWeekAfterPlanEnds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 15
        )))
        let first = workout("Strength", kind: .strength)
        let plan = plan(start: start, weeks: [TrainingPlanWeek(
            id: UUID(), weekNumber: 1, title: "Week 1",
            days: [TrainingPlanDay(id: UUID(), dayIndex: 1, title: "", sessions: [first])]
        )])

        let before = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: start))
        let after = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: start))
        XCTAssertTrue(ATHLTHTrainingPlanSchedule.sessions(in: plan, on: before, calendar: calendar).isEmpty)
        XCTAssertTrue(ATHLTHTrainingPlanSchedule.sessions(in: plan, on: after, calendar: calendar).isEmpty)
    }

    private func workout(_ title: String, kind: WorkoutKind) -> PlannedSession {
        PlannedSession(
            id: UUID(), title: title, kind: kind,
            scheduledStart: nil, durationMinutes: 40,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: nil
        )
    }

    private func plan(start: Date, weeks: [TrainingPlanWeek]) -> TrainingPlan {
        TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Test plan", summary: "",
            visibility: .privateOnly, version: 1, weeks: weeks, tags: [],
            createdAt: start, updatedAt: start, startDate: start
        )
    }
}
