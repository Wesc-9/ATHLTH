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
        XCTAssertEqual(ranked.most.first?.percentage, 33)
    }

    @MainActor
    func testAllLoggedMusclesUseAnAbsoluteWeeklyReference() {
        let profile = StrengthMuscleProfile(activations: [
            .init(region: .quads, score: 8),
            .init(region: .hamstrings, score: 7.5),
            .init(region: .glutes, score: 6.8),
            .init(region: .outerHip, score: 3),
            .init(region: .upperBack, score: 1),
            .init(region: .calves, score: 0.5)
        ])
        let summary = ATHLTHInsightsMuscleSummary(profile: profile, sessionCount: 18)
        let all = ATHLTHInsightsMuscleRanking.all(summary)
        XCTAssertEqual(all.count, 6)
        XCTAssertEqual(all.map(\.region), [
            .quads, .hamstrings, .glutes, .outerHip, .upperBack, .calves
        ])
        XCTAssertEqual(all.map(\.percentage), [67, 63, 57, 25, 8, 4])
        XCTAssertTrue(all.allSatisfy { !$0.needsLoadBalanceAttention })
        let extremes = ATHLTHInsightsMuscleRanking.extremes(summary)
        XCTAssertEqual(extremes.most.map(\.region), [.quads, .hamstrings])
        XCTAssertEqual(extremes.least.map(\.region), [.calves, .upperBack])
    }

    @MainActor
    func testRedAttentionNeedsEnoughComparativeEvidence() {
        let profile = StrengthMuscleProfile(activations: [
            .init(region: .chest, score: 10),
            .init(region: .biceps, score: 9),
            .init(region: .triceps, score: 8)
        ])
        let oneSession = ATHLTHInsightsMuscleSummary(
            profile: profile, sessionCount: 1)
        XCTAssertFalse(ATHLTHInsightsMuscleRanking.all(oneSession)
            .contains(where: \.needsLoadBalanceAttention))
        let twoRegions = ATHLTHInsightsMuscleSummary(
            profile: StrengthMuscleProfile(activations: [
                .init(region: .chest, score: 10),
                .init(region: .biceps, score: 9)
            ]), sessionCount: 10)
        XCTAssertFalse(ATHLTHInsightsMuscleRanking.all(twoRegions)
            .contains(where: \.needsLoadBalanceAttention))
    }

    @MainActor
    func testEvenlyTrainedMusclesDoNotAllBecomeRed() {
        let profile = StrengthMuscleProfile(activations: [
            .init(region: .quads, score: 10),
            .init(region: .hamstrings, score: 9.8),
            .init(region: .glutes, score: 9.6),
            .init(region: .calves, score: 9.4),
            .init(region: .upperBack, score: 9.2)
        ])
        let ranking = ATHLTHInsightsMuscleRanking.all(
            ATHLTHInsightsMuscleSummary(profile: profile, sessionCount: 18))
        XCTAssertEqual(ranking.first?.percentage, 83)
        XCTAssertFalse(ranking.contains(where: \.needsLoadBalanceAttention))
    }

    @MainActor
    func testUnknownMusclesRemainUncoloredAndUnranked() {
        let profile = StrengthMuscleProfile(activations: [
            .init(region: .chest, score: 4),
            .init(region: .lats, score: 0),
            .init(region: .quads, score: .nan)
        ])
        let all = ATHLTHInsightsMuscleRanking.all(
            ATHLTHInsightsMuscleSummary(profile: profile, sessionCount: 9))
        XCTAssertEqual(all.map(\.region), [.chest])
        XCTAssertEqual(all.first?.percentage, 33)
        XCTAssertFalse(all.first?.needsLoadBalanceAttention ?? true)
    }

    @MainActor
    func testSmallStrengthDoseIsNotAutomaticallyOneHundredPercent() {
        let oneSession = ATHLTHInsightsMuscleSummary(
            profile: StrengthMuscleProfile(activations: [
                .init(region: .quads, score: 3)
            ]), sessionCount: 1
        )
        let result = ATHLTHInsightsMuscleRanking.all(oneSession)
        XCTAssertEqual(result.first?.percentage, 25)
        XCTAssertFalse(result.first?.needsLoadBalanceAttention ?? true)
    }

    @MainActor
    func testOlderStrengthWorkContributesLessThanRecentWork() {
        func profile(_ score: Double) -> StrengthMuscleProfile {
            StrengthMuscleProfile(activations: [
                .init(region: .quads, score: score)
            ])
        }
        let fresh = ATHLTHInsightsMuscleSummary.estimateActivity(
            samples: [(date: now.addingTimeInterval(-86_400), profile: profile(4))],
            at: now
        )
        let old = ATHLTHInsightsMuscleSummary.estimateActivity(
            samples: [(date: now.addingTimeInterval(-21 * 86_400),
                       profile: profile(4))],
            at: now
        )
        XCTAssertGreaterThan(
            fresh.weeklyLoad[.quads] ?? 0, old.weeklyLoad[.quads] ?? 0
        )
        XCTAssertLessThan(
            fresh.weeklyLoad[.quads] ?? 0, 12
        )
    }

    @MainActor
    func testLongTermHistoryRaisesTheReferenceForHighlyTrainedMuscles() {
        let profile = StrengthMuscleProfile(activations: [
            .init(region: .quads, score: 30)
        ])
        let samples: [(date: Date, profile: StrengthMuscleProfile)] =
            [35, 42, 49, 56].map {
                (date: now.addingTimeInterval(-Double($0) * 86_400),
                 profile: profile)
            }
        let estimate = ATHLTHInsightsMuscleSummary.estimateActivity(
            samples: samples, at: now
        )
        XCTAssertTrue(estimate.reliableBaselineRegions.contains(.quads))
        XCTAssertEqual(estimate.previousWeeklyLoad[.quads] ?? 0, 10, accuracy: 0.01)

        let baseline = ATHLTHInsightsMuscleSummary(
            profile: StrengthMuscleProfile(activations: [
                .init(region: .quads, score: 10)
            ]),
            sessionCount: 4,
            weeklyLoad: [.quads: 10],
            previousWeeklyLoad: [:],
            reliableBaselineRegions: []
        )
        let personalized = ATHLTHInsightsMuscleSummary(
            profile: baseline.profile,
            sessionCount: 4,
            weeklyLoad: [.quads: 10],
            previousWeeklyLoad: [.quads: 20],
            reliableBaselineRegions: [.quads]
        )
        XCTAssertLessThan(
            ATHLTHInsightsMuscleRanking.all(personalized)[0].percentage,
            ATHLTHInsightsMuscleRanking.all(baseline)[0].percentage
        )
    }

    @MainActor
    func testRedFlagRequiresHistoricalEvidenceOfMeaningfulIncrease() {
        let profile = StrengthMuscleProfile(activations: [
            .init(region: .quads, score: 30)
        ])
        let withoutBaseline = ATHLTHInsightsMuscleSummary(
            profile: profile, sessionCount: 6, weeklyLoad: [.quads: 30]
        )
        XCTAssertFalse(
            ATHLTHInsightsMuscleRanking.all(withoutBaseline)[0].needsLoadBalanceAttention
        )

        let withBaseline = ATHLTHInsightsMuscleSummary(
            profile: profile, sessionCount: 6,
            weeklyLoad: [.quads: 30],
            previousWeeklyLoad: [.quads: 15],
            reliableBaselineRegions: [.quads]
        )
        XCTAssertTrue(
            ATHLTHInsightsMuscleRanking.all(withBaseline)[0].needsLoadBalanceAttention
        )
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
