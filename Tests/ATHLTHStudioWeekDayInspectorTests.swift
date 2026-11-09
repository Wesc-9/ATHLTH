import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHStudioWeekDayInspectorTests: XCTestCase {
    private func occurrence(planID: UUID?) -> ATHLTHStudioSchedule.Occurrence {
        let workout = PlannedSession(
            id: UUID(),
            title: "4 x 4 intervals",
            kind: .running,
            scheduledStart: Date(),
            durationMinutes: 49,
            targetDistanceKilometers: 8.6,
            targetPaceSecondsPerKilometer: 341,
            routeID: nil,
            exercises: [],
            notes: nil
        )
        return .init(
            id: "\(planID?.uuidString ?? "standalone"):\(workout.id)",
            workout: workout,
            date: Date(),
            planTitle: planID == nil ? nil : "Half marathon",
            planID: planID
        )
    }

    func testPlannedWorkoutCanStartOnlyWhenNotCompletedOrSkipped() {
        let scheduled = occurrence(planID: UUID())
        XCTAssertTrue(ATHLTHStudioWeekDayInspectorPolicy.canStart(
            scheduled, completed: false, skipped: false
        ))
        XCTAssertFalse(ATHLTHStudioWeekDayInspectorPolicy.canStart(
            scheduled, completed: true, skipped: false
        ))
        XCTAssertFalse(ATHLTHStudioWeekDayInspectorPolicy.canStart(
            scheduled, completed: false, skipped: true
        ))
    }

    func testStandaloneWorkoutOpensExistingDetailsInsteadOfStartingPlan() {
        let standalone = occurrence(planID: nil)
        XCTAssertFalse(ATHLTHStudioWeekDayInspectorPolicy.canStart(
            standalone, completed: false, skipped: false
        ))
    }

    func testDateSelectionUsesRealScheduledAndRecordedWeekItems() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let tuesday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 10, hour: 18
        )))
        var standalone = occurrence(planID: nil).workout
        standalone.scheduledStart = tuesday
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 9
        )))
        let result = ATHLTHStudioHomeWeek.make(
            plans: [],
            standalone: [standalone],
            recorded: [],
            now: monday,
            calendar: calendar
        )
        XCTAssertEqual(result.days.count, 7)
        XCTAssertEqual(result.days[1].planned.first?.workout.id, standalone.id)
        XCTAssertTrue(result.days[0].planned.isEmpty)
    }
}
