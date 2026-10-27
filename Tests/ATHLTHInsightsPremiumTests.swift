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

    @MainActor
    func testOnlyMeasuredMusclesAppearInHighLowRanking() {
        let profile = StrengthMuscleProfile(activations: [
            .init(region: .quads, score: 6),
            .init(region: .hamstrings, score: 3),
            .init(region: .glutes, score: 1),
            .init(region: .calves, score: 0.5)
        ])
        let summary = ATHLTHInsightsMuscleSummary(profile: profile, sessionCount: 4)
        let ranked = ATHLTHInsightsMuscleRanking.extremes(summary)
        XCTAssertEqual(ranked.most.map(\.region), [.quads, .hamstrings])
        XCTAssertEqual(ranked.least.map(\.region), [.calves, .glutes])
        XCTAssertEqual(ranked.most.count, 2)
        XCTAssertEqual(ranked.least.count, 2)
        XCTAssertFalse((ranked.most + ranked.least).contains { $0.percentage < 0 })
    }

    func testUnmeasuredMusclesAreNotInventedAsZeroPercent() {
        let profile = StrengthMuscleProfile(activations: [
            .init(region: .quads, score: 4)
        ])
        let summary = ATHLTHInsightsMuscleSummary(profile: profile, sessionCount: 1)
        let ranked = ATHLTHInsightsMuscleRanking.extremes(summary)
        XCTAssertEqual(ranked.most.map(\.region), [.quads])
        XCTAssertTrue(ranked.least.isEmpty)
        XCTAssertEqual(ranked.most.first?.percentage, 100)
    }

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
