import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlanMoveWeekPreviewTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func workout(_ kind: WorkoutKind) -> PlannedSession {
        PlannedSession(
            id: UUID(), title: "Workout", kind: kind,
            scheduledStart: nil, durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
    }

    private func make(
        sessions: [(Int, [PlannedSession])],
        start: Date
    ) -> (TrainingPlan, ATHLTHPlanReviewMoveProposal.Proposal) {
        let days = (1...7).map { index in
            TrainingPlanDay(
                id: UUID(), dayIndex: index, title: "Day \(index)",
                sessions: sessions.first { $0.0 == index }?.1 ?? []
            )
        }
        let week = TrainingPlanWeek(
            id: UUID(), weekNumber: 1, title: "Week 1", days: days
        )
        let plan = TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Plan", summary: "",
            visibility: .privateOnly, version: 5, weeks: [week],
            tags: [], createdAt: start, updatedAt: start, startDate: start
        )
        let source = days[0]
        let target = days.first(where: { $0.sessions.isEmpty })!
        let preview = ATHLTHPlanReviewMoveProposal.Proposal(
            planID: plan.id, expectedPlanVersion: plan.version,
            weekID: week.id, sourceDayID: source.id,
            targetDayID: target.id, workoutID: source.sessions[0].id,
            workoutTitle: "Workout", sourceDate: start,
            targetDate: calendar.date(
                byAdding: .day, value: target.dayIndex - 1, to: start
            )!, reason: "Review"
        )
        return (plan, preview)
    }

    func testBeforeAfterKeepsSessionCountAndShowsCostOfUsingRestDay() {
        let start = calendar.startOfDay(for: Date())
        let (plan, preview) = make(
            sessions: [(1, [workout(.running), workout(.strength)])],
            start: start
        )
        let impact = ATHLTHPlanMoveWeekPreview.summarize(
            preview, in: plan, referenceDate: start, calendar: calendar
        )
        XCTAssertEqual(impact?.days.count, 7)
        XCTAssertEqual(impact?.activeDaysBefore, 1)
        XCTAssertEqual(impact?.activeDaysAfter, 2)
        XCTAssertEqual(impact?.days[0].beforeCount, 2)
        XCTAssertEqual(impact?.days[0].afterCount, 1)
        XCTAssertEqual(impact?.days[1].beforeCount, 0)
        XCTAssertEqual(impact?.days[1].afterCount, 1)
        XCTAssertEqual(impact?.days.map(\.beforeCount).reduce(0,+), 2)
        XCTAssertEqual(impact?.days.map(\.afterCount).reduce(0,+), 2)
        XCTAssertTrue(impact?.usesFreeDay == true)
        XCTAssertEqual(plan.version, 5)
        XCTAssertEqual(plan.weeks[0].days[0].sessions.count, 2)
    }

    func testAlternativeDayCanBeSelectedButOccupiedDayCannot() {
        let start = calendar.startOfDay(for: Date())
        let (plan, preview) = make(
            sessions: [
                (1, [workout(.running)]),
                (2, [workout(.strength)])
            ], start: start
        )
        let day4 = plan.weeks[0].days[3]
        let chosen = ATHLTHPlanMoveWeekPreview.choosing(
            day4.id, from: preview, in: plan,
            referenceDate: start, calendar: calendar
        )
        XCTAssertEqual(chosen?.targetDayID, day4.id)
        XCTAssertNil(ATHLTHPlanMoveWeekPreview.choosing(
            plan.weeks[0].days[1].id, from: preview, in: plan,
            referenceDate: start, calendar: calendar
        ))
        XCTAssertEqual(plan.weeks[0].days[3].sessions.count, 0)
    }

    func testStalePlanAndPastDayHaveNoValidPreview() {
        let start = calendar.startOfDay(for: Date())
        let (plan, preview) = make(
            sessions: [(1, [workout(.running)])], start: start
        )
        var updated = plan
        updated.version += 1
        XCTAssertNil(ATHLTHPlanMoveWeekPreview.summarize(
            preview, in: updated,
            referenceDate: start, calendar: calendar
        ))
        let tomorrow = calendar.date(
            byAdding: .day, value: 1, to: start
        )!
        XCTAssertTrue(ATHLTHPlanMoveWeekPreview.destinations(
            preview, in: plan,
            referenceDate: tomorrow, calendar: calendar
        ).isEmpty)
    }

    func testNoDestinationCanCreateNewThreeDayRunStreak() {
        let start = calendar.startOfDay(for: Date())
        let (plan, preview) = make(
            sessions: [
                (1, [workout(.running)]),
                (3, [workout(.running)]),
                (4, [workout(.running)])
            ], start: start
        )
        let choices = ATHLTHPlanMoveWeekPreview.destinations(
            preview, in: plan,
            referenceDate: start, calendar: calendar
        )
        // Moving the first run to day 2 would create a day-2/3/4 streak.
        XCTAssertFalse(choices.contains {
            $0.dayID == plan.weeks[0].days[1].id
        })
    }
}
