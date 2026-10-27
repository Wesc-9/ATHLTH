import Foundation
import HealthKit
import SwiftUI
import XCTest
@testable import ATHLTH

final class ATHLTHInsightsPremiumTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private func workout(daysAgo: Int, durationMinutes: Int) -> WorkoutSummary {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday)!
        let start = day.addingTimeInterval(12 * 3600)
        let duration = TimeInterval(durationMinutes * 60)
        return WorkoutSummary(workout: HKWorkout(
            activityType: .running,
            start: start,
            end: start.addingTimeInterval(duration),
            duration: duration,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: nil
        ))
    }

    func testSectionsPreserveFourDistinctDestinations() {
        XCTAssertEqual(
            ATHLTHInsightsSection.allCases,
            [.overview, .health, .training, .development]
        )
        XCTAssertEqual(Set(ATHLTHInsightsSection.allCases.map(\.title)).count, 4)
    }

    func testWeekChartUsesRealWorkoutsAndExcludesOldHistory() {
        let days = ATHLTHInsightsTrainingDay.make(
            from: [workout(daysAgo: 0, durationMinutes: 45),
                   workout(daysAgo: 2, durationMinutes: 30),
                   workout(daysAgo: 2, durationMinutes: 20),
                   workout(daysAgo: 20, durationMinutes: 180)],
            at: now
        )
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.reduce(0) { $0 + $1.sessions }, 3)
        XCTAssertEqual(days.reduce(0) { $0 + $1.minutes }, 95, accuracy: 0.001)
        XCTAssertEqual(days[4].sessions, 2)
        XCTAssertEqual(days[6].sessions, 1)
    }

    func testMissingHealthHistoryDoesNotInventActivity() {
        let days = ATHLTHInsightsTrainingDay.make(from: [], at: now)
        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(days.allSatisfy { $0.sessions == 0 && $0.minutes == 0 })
    }

    func testMuscleMapWithoutFinishedStrengthSessionsIsNeutral() {
        let summary = ATHLTHInsightsMuscleSummary.make(from: [], at: now)
        XCTAssertEqual(summary.sessionCount, 0)
        XCTAssertTrue(summary.profile.activations.isEmpty)
        XCTAssertEqual(summary.profile.intensity(for: .quads), 0)
    }

    private func checkIn(
        daysAgo: Int,
        energy: Int? = nil,
        stress: Int? = nil,
        soreness: Int? = nil,
        motivation: Int? = nil,
        reference: Date? = nil
    ) -> RecoverySorenessEntry {
        let today = Calendar.current.startOfDay(for: reference ?? now)
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today)!
        return RecoverySorenessEntry(
            date: day,
            ratings: [:],
            energy: energy,
            stress: stress,
            overallSoreness: soreness,
            motivation: motivation
        )
    }

    func testSelfReportTrendUsesOnlyAnsweredDaysAndFields() {
        let entries = [
            checkIn(daysAgo: 0, energy: 4, stress: 2),
            checkIn(daysAgo: 1, stress: 5),
            checkIn(daysAgo: 2, energy: 3),
            checkIn(daysAgo: 10, energy: 2),
            checkIn(daysAgo: 18, motivation: 5)
        ]

        let week = ATHLTHCheckInTrends.points(
            entries: entries, metric: .energy, days: 7, at: now
        )
        XCTAssertEqual(week.count, 2)
        XCTAssertEqual(week.map(\.value), [3, 4])
        XCTAssertEqual(ATHLTHCheckInTrends.average(week)!, 3.5, accuracy: 0.001)

        let month = ATHLTHCheckInTrends.points(
            entries: entries, metric: .energy, days: 30, at: now
        )
        XCTAssertEqual(month.count, 3)
        XCTAssertEqual(ATHLTHCheckInTrends.points(
            entries: entries, metric: .soreness, days: 30, at: now
        ).count, 0, "Unanswered soreness must not be synthesized as zero")
    }

    func testSelfReportTrendComparisonRequiresEvidenceInBothPeriods() {
        var entries = (0...2).map { checkIn(daysAgo: $0, energy: 4) }
        entries += (7...9).map { checkIn(daysAgo: $0, energy: 2) }

        let change = ATHLTHCheckInTrends.change(
            entries: entries, metric: .energy, days: 7, at: now
        )
        XCTAssertEqual(change!, 2, accuracy: 0.001)
        XCTAssertNil(ATHLTHCheckInTrends.change(
            entries: entries, metric: .motivation, days: 7, at: now
        ))
        XCTAssertTrue(ATHLTHCheckInMetric.stress.lowerIsBetter)
        XCTAssertTrue(ATHLTHCheckInMetric.soreness.lowerIsBetter)
        XCTAssertFalse(ATHLTHCheckInMetric.energy.lowerIsBetter)
    }

    func testCheckInRetentionExtendsToOneYearWithoutLosingExistingAnswers() throws {
        let defaults = UserDefaults(
            suiteName: "athlth.test.insights.trend.\(UUID().uuidString)"
        )!
        let kept = checkIn(daysAgo: 45, energy: 3, stress: 4, reference: .now)
        let expired = checkIn(daysAgo: 400, motivation: 1, reference: .now)
        defaults.set(
            try JSONEncoder().encode([kept, expired]),
            forKey: "recovery.soreness.entries"
        )
        let store = RecoverySorenessStore(defaults: defaults)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.energy, 3)
        XCTAssertEqual(store.entries.first?.stress, 4)
        XCTAssertNil(store.entries.first?.motivation)
    }

    @MainActor
    func testSelfReportTrendCardFitsCompactPhones() {
        for width in [320.0, 375.0, 430.0] {
            let card = ATHLTHDailyWellbeingTrendCard(
                entries: [],
                onEdit: {}
            )
            let controller = UIHostingController(rootView: card)
            controller.loadViewIfNeeded()
            let allowed = width - 32
            let size = controller.sizeThatFits(
                in: CGSize(width: allowed, height: 940)
            )
            XCTAssertLessThanOrEqual(size.width, allowed + 1)
        }
    }

    @MainActor
    func testCompactFourTabNavigationFitsPhones() {
        for width in [320.0, 375.0, 430.0] {
            let view = ATHLTHInsightsNavigation(selection: .constant(.overview))
            let controller = UIHostingController(rootView: view)
            controller.loadViewIfNeeded()
            let allowed = width - 32
            let size = controller.sizeThatFits(in: CGSize(width: allowed, height: 150))
            XCTAssertLessThanOrEqual(size.width, allowed + 1)
        }
    }
}
