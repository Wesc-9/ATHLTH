import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlanReviewAdvisorTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private let start = Date(timeIntervalSince1970: 1_900_000_000)

    private func workout(
        kind: WorkoutKind = .running,
        duration: Int? = 35
    ) -> PlannedSession {
        PlannedSession(
            id: UUID(), title: "Workout", kind: kind,
            scheduledStart: nil, durationMinutes: duration,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
    }

    private func week(_ number: Int, days: [(Int, [PlannedSession])])
        -> TrainingPlanWeek {
        TrainingPlanWeek(
            id: UUID(), weekNumber: number, title: "Week \(number)",
            days: (1...7).map { index in
                TrainingPlanDay(
                    id: UUID(), dayIndex: index, title: "Day \(index)",
                    sessions: days.first(where: { $0.0 == index })?.1 ?? []
                )
            }
        )
    }

    private func plan(
        weeks: [TrainingPlanWeek], startDate: Date?
    ) -> TrainingPlan {
        TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Plan",
            summary: "", visibility: .privateOnly, version: 1,
            weeks: weeks, tags: [], createdAt: start, updatedAt: start,
            startDate: startDate
        )
    }

    func testMissingDurationSuggestsCorrectFutureDay() {
        let date = cal.startOfDay(for: start)
        let targetWeek = week(1, days: [
            (3, [workout(duration: nil)]),
            (4, [workout(duration: 40)])
        ])
        let suggestions = ATHLTHPlanReviewAdvisor.inspect(
            plan(weeks: [targetWeek], startDate: date),
            referenceDate: date, calendar: cal
        )
        let missing = suggestions.filter { $0.kind == .missingDuration }
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing.first?.weekID, targetWeek.id)
        XCTAssertEqual(missing.first?.dayID, targetWeek.days[2].id)
    }

    func testPastWorkoutsAreNotSuggestedForEditing() {
        let date = cal.startOfDay(for: start)
        let targetWeek = week(1, days: [
            (1, [workout(duration: nil)]),
            (7, [workout(duration: nil)])
        ])
        let reference = cal.date(byAdding: .day, value: 3, to: date)!
        let report = ATHLTHPlanReviewAdvisor.inspect(
            plan(weeks: [targetWeek], startDate: date),
            referenceDate: reference, calendar: cal
        )
        XCTAssertFalse(report.contains { $0.dayID == targetWeek.days[0].id })
        XCTAssertTrue(report.contains { $0.dayID == targetWeek.days[6].id })
    }

    func testIncreaseSuggestionUsesRealWeekNumbersAndNoGuessForGaps() {
        let date = cal.startOfDay(for: start)
        let first = week(1, days: [(1, [workout()])])
        let second = week(2, days: [
            (1, [workout()]), (2, [workout()]), (3, [workout()])
        ])
        let fourth = week(4, days: [
            (1, [workout()]), (2, [workout()]), (3, [workout()]),
            (4, [workout()]), (5, [workout()]), (6, [workout()])
        ])
        let advice = ATHLTHPlanReviewAdvisor.inspect(
            plan(weeks: [first, second, fourth], startDate: date),
            referenceDate: date, calendar: cal
        )
        let frequency = advice.filter { $0.kind == .increasingFrequency }
        XCTAssertEqual(frequency.count, 1)
        XCTAssertEqual(frequency.first?.weekID, second.id)
        XCTAssertNil(frequency.first?.dayID)
    }

    func testNoStartDateProducesNoSpuriousFutureSuggestions() {
        let advice = ATHLTHPlanReviewAdvisor.inspect(
            plan(
                weeks: [week(1, days: [(1, [workout(duration: nil)])])],
                startDate: nil
            ),
            referenceDate: start, calendar: cal
        )
        XCTAssertTrue(advice.isEmpty)
    }

    func testExistingWeekFindingsCanBeOpenedAndNeverChangeThePlan() {
        let date = cal.startOfDay(for: start)
        let targetWeek = week(1, days: [
            (1, [workout(kind: .running)]),
            (2, [workout(kind: .running)]),
            (3, [workout(kind: .running)])
        ])
        let original = plan(weeks: [targetWeek], startDate: date)
        let originalVersion = original.version
        let originalIDs = original.weeks.flatMap(\.days)
            .flatMap(\.sessions).map(\.id)
        let results = ATHLTHPlanReviewAdvisor.inspect(
            original, referenceDate: date, calendar: cal
        )
        XCTAssertTrue(results.contains { $0.kind == .consecutiveRuns })
        XCTAssertEqual(original.version, originalVersion)
        XCTAssertEqual(
            original.weeks.flatMap(\.days).flatMap(\.sessions).map(\.id),
            originalIDs
        )
    }
}
