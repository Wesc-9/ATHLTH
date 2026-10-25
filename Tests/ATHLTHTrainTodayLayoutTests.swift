import SwiftUI
import XCTest
@testable import ATHLTH

final class ATHLTHTrainTodayLayoutTests: XCTestCase {
    @MainActor
    func testWorkoutSuggestionsPreferRelevantAndDifferentCategories() {
        func make(_ category: String, _ difficulty: String, _ sortOrder: Int,
                  tags: [String] = []) -> WorkoutTemplateCatalogEntry {
            let block = WorkoutTemplateBlock(
                sequence: 1, kind: .rest, title: "Recovery",
                exerciseSlug: nil, distanceMeters: nil,
                repetitions: nil, durationSeconds: 60,
                targetWeightKilograms: nil, loadNote: nil, notes: nil
            )
            return WorkoutTemplateCatalogEntry(
                id: UUID(), slug: "\(category)-\(sortOrder)",
                title: "\(category)-\(sortOrder)", summary: "",
                category: category, difficulty: difficulty,
                estimatedDurationMinutes: 30, tags: tags,
                sourceLabel: nil, sourceURL: nil,
                blocks: [block], sortOrder: sortOrder
            )
        }

        let entries = [
            make("hybrid", "Advanced", 1, tags: ["hyrox"]),
            make("running", "Beginner", 2),
            make("running", "Beginner", 3),
            make("strength", "Beginner", 4)
        ]
        let chosen = TrainWorkoutSuggestionPolicy.pick(
            entries, preferredKind: .strength
        )
        XCTAssertEqual(chosen.count, 2)
        XCTAssertEqual(chosen[0].category, "strength")
        XCTAssertEqual(chosen[1].category, "running")
        XCTAssertFalse(chosen.contains(where: { $0.tags.contains("hyrox") }))
        let withoutPlan = TrainWorkoutSuggestionPolicy.pick(
            entries, preferredKind: nil
        )
        XCTAssertEqual(Set(withoutPlan.map(\.category)).count, 2)
        XCTAssertEqual(TrainWorkoutSuggestionPolicy.pick(
            [entries[0]], preferredKind: nil
        ).count, 0)
    }

    @MainActor
    func testOverviewDistinguishesUnscheduledFromCompletedActivity() {
        XCTAssertEqual(
            TrainTodayOverviewPolicy.status(
                hasPlan: false, hasRecordedWorkoutToday: false
            ),
            .noActivePlan
        )
        XCTAssertEqual(
            TrainTodayOverviewPolicy.status(
                hasPlan: true, hasRecordedWorkoutToday: false
            ),
            .noWorkoutInPlan
        )
        XCTAssertEqual(
            TrainTodayOverviewPolicy.status(
                hasPlan: true, hasRecordedWorkoutToday: true
            ),
            .trainedToday
        )
        XCTAssertEqual(
            TrainTodayOverviewPolicy.status(
                hasPlan: false, hasRecordedWorkoutToday: true
            ),
            .trainedToday
        )
    }

    @MainActor
    func testCompletedIPhoneWorkoutCountsWithoutAppleHealthSync() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let completedToday = day.addingTimeInterval(-1800)
        let completedYesterday = day.addingTimeInterval(-86_400)

        // A local phone workout is valid even when HealthKit has no results.
        XCTAssertTrue(TrainTodayOverviewPolicy.hasRecordedWorkout(
            on: day,
            healthStartDates: [],
            strengthEndDates: [],
            phoneCompletedDates: [completedToday]
        ))
        XCTAssertFalse(TrainTodayOverviewPolicy.hasRecordedWorkout(
            on: day,
            healthStartDates: [],
            strengthEndDates: [],
            phoneCompletedDates: []
        ))
        XCTAssertFalse(TrainTodayOverviewPolicy.hasRecordedWorkout(
            on: day,
            healthStartDates: [],
            strengthEndDates: [],
            phoneCompletedDates: [completedYesterday]
        ))

        // Existing HealthKit and strength history continue to count.
        XCTAssertTrue(TrainTodayOverviewPolicy.hasRecordedWorkout(
            on: day,
            healthStartDates: [completedToday],
            strengthEndDates: [],
            phoneCompletedDates: []
        ))
        XCTAssertTrue(TrainTodayOverviewPolicy.hasRecordedWorkout(
            on: day,
            healthStartDates: [],
            strengthEndDates: [completedToday],
            phoneCompletedDates: []
        ))
    }

    @MainActor
    func testDayReadinessRequiresFreshCompleteBaseline() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = now.addingTimeInterval(-6 * 3600)
        let stale = now.addingTimeInterval(-60 * 3600)
        let valid = RecoveryReadinessSummary(
            score: 62,
            state: .takeItEasy,
            detail: "",
            baselineDays: 8,
            averageSleepDuration: nil,
            baselineHRVMilliseconds: nil,
            baselineRestingHeartRate: nil
        )
        XCTAssertEqual(
            TrainTodayOverviewPolicy.reliableReadiness(
                valid,
                sleepEnd: recent,
                hrvDate: recent,
                restingHeartRateDate: recent,
                now: now
            )?.score,
            62
        )
        XCTAssertNil(
            TrainTodayOverviewPolicy.reliableReadiness(
                valid,
                sleepEnd: recent,
                hrvDate: stale,
                restingHeartRateDate: recent,
                now: now
            )
        )
        XCTAssertNil(
            TrainTodayOverviewPolicy.reliableReadiness(
                valid,
                sleepEnd: nil,
                hrvDate: recent,
                restingHeartRateDate: recent,
                now: now
            )
        )
        XCTAssertNil(
            TrainTodayOverviewPolicy.reliableReadiness(
                RecoveryReadinessSummary(
                    score: 62,
                    state: .ready,
                    detail: "",
                    baselineDays: 2,
                    averageSleepDuration: nil,
                    baselineHRVMilliseconds: nil,
                    baselineRestingHeartRate: nil
                ),
                sleepEnd: recent,
                hrvDate: recent,
                restingHeartRateDate: recent,
                now: now
            )
        )
    }

    @MainActor
    func testQuickStartDeviceButtonsFitCompactPhones() {
        for width in [320.0, 375.0, 430.0] {
            for watchAvailable in [false, true] {
                for canStart in [false, true] {
                    for preferAppleWatch in [false, true] {
                        let bar = ATHLTHQuickStartDeviceLaunchBar(
                            watchAvailable: watchAvailable,
                            onIPhone: {},
                            onAppleWatch: {},
                            preferAppleWatch: preferAppleWatch,
                            canStart: canStart
                        )
                        let host = UIHostingController(rootView: bar)
                        host.loadViewIfNeeded()
                        let measured = host.sizeThatFits(
                            in: CGSize(width: width, height: 600)
                        )
                        XCTAssertLessThanOrEqual(
                            measured.width, width + 1,
                            "Quick Start actions overflow a \\(Int(width))-pt phone"
                        )
                    }
                }
            }
        }
    }

    @MainActor
    func testTodaySurfaceFitsCompactPhoneWidths() {
        let plan = TrainingPlan(
            id: UUID(),
            ownerID: UUID(),
            title: "Weekly plan",
            summary: "",
            visibility: .privateOnly,
            version: 1,
            weeks: [],
            tags: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        // Plan-free and unscheduled days show a compact overview.
        // Verify it and the remaining heroes fit narrow phone widths.
        let scenarios: [TrainingPlan?] = [nil, plan]
        // Quick Train's friend strip requires the same social environment
        // injected by the production tab root.
        let social = SocialStore()
        for width in [320.0, 375.0, 430.0] {
            for currentPlan in scenarios {
                for hasActiveWorkout in [false, true] {
                let today = ATHLTHTrainTodayPremiumView(
                    workoutCatalog: WorkoutTemplateCatalogStore(),
                    plan: currentPlan,
                    sessions: [],
                    completedIDs: [],
                    healthCompletedIDs: [],
                    completionFraction: 0,
                    planPosition: "",
                    hasActiveWorkout: hasActiveWorkout,
                    activeWorkoutKind: nil,
                    lastCompletedWorkoutKind: nil,
                    activeWorkoutCard: nil,
                    hasRecordedWorkoutToday: false,
                    todaysReadiness: nil,
                    onChooseSuggestedWorkout: { _ in },
                    onOpenPlan: {},
                    onCreatePlan: {},
                    onOpenLibrary: {},
                    onStartWorkout: { _, _ in },
                    onWorkoutDetails: { _, _ in },
                    onAcceptAlternative: { _, _ in },
                    onUndoAlternative: { _ in },
                    onQuickTrain: { _ in },
                    onQuickCycling: {},
                    onQuickCustom: { _ in },
                    onGhostRace: {}
                )

                let host = UIHostingController(
                    rootView: today
                        .environmentObject(social)
                        .environmentObject(AppSessionStore())
                        .environmentObject(GoalStore())
                )
                host.loadViewIfNeeded()
                let measured = host.sizeThatFits(
                    in: CGSize(width: width, height: 1_600)
                )
                XCTAssertLessThanOrEqual(
                    measured.width,
                    width + 1,
                    "Today content exceeds a \(Int(width))-point viewport"
                )
                }
            }
        }
    }
}
