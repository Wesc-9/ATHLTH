import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainStandaloneCalendarTests: XCTestCase {
    func testScheduledStandaloneSessionIsVisibleWithoutActivePlan() {
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        var workout = PlannedSession(
            id: UUID(), title: "Morning walk", kind: .walking,
            scheduledStart: day, durationMinutes: 30,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        workout.durationMinutes = 30
        let today = HomeTodayCalendarSchedule.workouts(
            plan: nil, standalone: [workout], on: day, calendar: calendar
        )
        XCTAssertEqual(today.map(\.id), [workout.id])
        XCTAssertEqual(today.first?.kind, .walking)
    }

    func testStandaloneOutsideCalendarDayIsNotShownOnToday() {
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let otherDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let workout = PlannedSession(
            id: UUID(), title: "Next day", kind: .running,
            scheduledStart: otherDay, durationMinutes: 30,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        XCTAssertTrue(HomeTodayCalendarSchedule.workouts(
            plan: nil, standalone: [workout], on: day, calendar: calendar
        ).isEmpty)
    }
}
