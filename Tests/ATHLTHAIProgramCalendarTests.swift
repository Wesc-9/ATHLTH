import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAIProgramCalendarTests: XCTestCase {
    func testAIWeekdaysRemainCalendarWeekdaysWhenProgramBeginsThursday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try XCTUnwrap(calendar.date(from: .init(
            year: 2026, month: 10, day: 15
        )))
        let monday = AIProgramDraftSession(
            title: "Monday run", kind: "running",
            durationMinutes: 40, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, notes: nil, exercises: []
        )
        let thursday = AIProgramDraftSession(
            title: "Thursday strength", kind: "strength",
            durationMinutes: 45, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, notes: nil, exercises: []
        )
        let draft = AIProgramDraft(title: "Calendar", summary: "", weeks: [
            AIProgramDraftWeek(weekNumber: 1, title: "Week 1", days: [
                AIProgramDraftDay(dayIndex: 1, title: "Monday", sessions: [monday]),
                AIProgramDraftDay(dayIndex: 4, title: "Thursday", sessions: [thursday])
            ])
        ])
        let plan = draft.makeTrainingPlan(ownerID: UUID(), startDate: start)
        XCTAssertEqual(plan.weeks[0].days[0].sessions.map(\.title), ["Thursday strength"])
        XCTAssertEqual(plan.weeks[0].days[4].sessions.map(\.title), ["Monday run"])
        let nextMonday = try XCTUnwrap(calendar.date(byAdding: .day, value: 4, to: start))
        XCTAssertEqual(ATHLTHTrainingPlanSchedule.sessions(
            in: plan, on: nextMonday, calendar: calendar
        ).map(\.title), ["Monday run"])
    }
}
