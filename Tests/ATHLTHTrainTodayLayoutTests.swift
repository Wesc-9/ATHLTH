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

    func testBodyWeightGoalShowsMeasuredKgNotMilestonePercentage() {
        let target = GoalTarget(
            metric: .bodyWeightKilograms,
            targetValue: 71,
            unit: "kg",
            baselineValue: 78
        )
        guard let result = ATHLTHTrainWeightGoalProgress.evaluate(
            target: target, latestWeightKilograms: 73.8
        ) else {
            XCTFail("A finite Apple Health sample and a real baseline must produce progress")
            return
        }
        XCTAssertEqual(result.achievedKilograms, 4.2, accuracy: 0.0001)
        XCTAssertEqual(result.targetKilograms, 7, accuracy: 0.0001)
        XCTAssertEqual(result.completionFraction, 0.6, accuracy: 0.0001)

        let beyondTarget = ATHLTHTrainWeightGoalProgress.evaluate(
            target: target, latestWeightKilograms: 68
        )
        XCTAssertEqual(beyondTarget?.completionFraction, 1)

        let weightGain = GoalTarget(
            metric: .bodyWeightKilograms, targetValue: 75,
            unit: "kg", baselineValue: 70
        )
        let gain = ATHLTHTrainWeightGoalProgress.evaluate(
            target: weightGain, latestWeightKilograms: 72
        )
        XCTAssertEqual(gain?.achievedKilograms, 2)
        XCTAssertEqual(gain?.completionFraction, 0.4)

        let movingAway = ATHLTHTrainWeightGoalProgress.evaluate(
            target: target, latestWeightKilograms: 79
        )
        XCTAssertEqual(movingAway?.achievedKilograms, -1)
        XCTAssertEqual(movingAway?.completionFraction, 0)
    }

    func testTodayWeightGoalNeverFallsBackToMilestonePercentage() {
        let weight = GoalTarget(
            metric: .bodyWeightKilograms, targetValue: 71,
            unit: "kg", baselineValue: 78
        )
        let milestone = GoalMilestone(
            title: "Halfway", targetDescription: "First milestone",
            completedAt: .now
        )
        let goal = ATHLTHGoal(
            title: "Reach 71 kg", category: .body,
            dataSource: .appleHealth, target: weight,
            milestones: [milestone, GoalMilestone(
                title: "Goal", targetDescription: "Final milestone"
            )]
        )
        XCTAssertEqual(goal.progress, 0.5)
        XCTAssertNil(ATHLTHTrainWeightGoalProgress.visibleFraction(
            goal: goal, latestWeightKilograms: nil
        ), "A 50% milestone status cannot be presented as measured body weight")
        XCTAssertEqual(ATHLTHTrainWeightGoalProgress.visibleFraction(
            goal: goal, latestWeightKilograms: 73.8
        ) ?? -1, 0.6, accuracy: 0.0001)

        let nonBodyGoal = ATHLTHGoal(
            title: "Strength", category: .strength,
            dataSource: .manual, milestones: goal.milestones
        )
        XCTAssertEqual(ATHLTHTrainWeightGoalProgress.visibleFraction(
            goal: nonBodyGoal, latestWeightKilograms: nil
        ), 0.5)
    }

    func testWeightGoalDoesNotInventProgressWhenHealthDataOrBaselineIsMissing() {
        let missingBaseline = GoalTarget(
            metric: .bodyWeightKilograms, targetValue: 71,
            unit: "kg", baselineValue: nil
        )
        let valid = GoalTarget(
            metric: .bodyWeightKilograms, targetValue: 71,
            unit: "kg", baselineValue: 78
        )
        let sameWeight = GoalTarget(
            metric: .bodyWeightKilograms, targetValue: 78,
            unit: "kg", baselineValue: 78
        )
        let otherMetric = GoalTarget(
            metric: .strengthWeightKilograms, targetValue: 100,
            unit: "kg", baselineValue: 80
        )
        XCTAssertNil(ATHLTHTrainWeightGoalProgress.evaluate(
            target: missingBaseline, latestWeightKilograms: 73.8
        ))
        XCTAssertNil(ATHLTHTrainWeightGoalProgress.evaluate(
            target: valid, latestWeightKilograms: nil
        ))
        XCTAssertNil(ATHLTHTrainWeightGoalProgress.evaluate(
            target: sameWeight, latestWeightKilograms: 73.8
        ))
        XCTAssertNil(ATHLTHTrainWeightGoalProgress.evaluate(
            target: otherMetric, latestWeightKilograms: 90
        ))
        XCTAssertNil(ATHLTHTrainWeightGoalProgress.evaluate(
            target: valid, latestWeightKilograms: .nan
        ))
    }

    func testTrainDayChangeHonorsCalendarDateAndDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: 30
            ))!
        }
        // 2026-03-08 crosses the spring DST change. Three hours later,
        // the day is still the same; Train must not reset day-scoped state.
        let beforeDST = local(2026, 3, 8, 1)
        let afterDST = local(2026, 3, 8, 4)
        let nextDay = local(2026, 3, 9, 0)
        XCTAssertFalse(ATHLTHTrainDayChangePolicy.needsRefresh(
            displayedDay: beforeDST, now: afterDST, calendar: calendar
        ))
        XCTAssertTrue(ATHLTHTrainDayChangePolicy.needsRefresh(
            displayedDay: beforeDST, now: nextDay, calendar: calendar
        ))
        XCTAssertFalse(ATHLTHTrainDayChangePolicy.needsRefresh(
            displayedDay: nextDay, now: nextDay, calendar: calendar
        ))
    }

    func testTodayAgendaDoesNotDuplicateMainWorkoutDuringLiveRecording() {
        func workout(_ name: String) -> PlannedSession {
            PlannedSession(
                id: UUID(), title: name, kind: .strength,
                scheduledStart: .now, durationMinutes: 45,
                targetDistanceKilometers: nil,
                targetPaceSecondsPerKilometer: nil,
                routeID: nil, exercises: [], notes: nil
            )
        }
        let primary = workout("Upper body")
        let extra = workout("Intervals")
        let sessions = [primary, extra]

        let active = ATHLTHTrainTodayAgendaPolicy.remainingSessions(
            sessions, primaryWorkoutID: primary.id, completedIDs: [],
            hasPlan: true, hasActiveWorkout: true
        )
        XCTAssertEqual(active.map(\.id), [extra.id],
                       "The live card replaces the primary session, not the other planned work")

        let scheduled = ATHLTHTrainTodayAgendaPolicy.remainingSessions(
            sessions, primaryWorkoutID: primary.id, completedIDs: [],
            hasPlan: true, hasActiveWorkout: false
        )
        XCTAssertEqual(scheduled.map(\.id), [extra.id])

        let noPlan = ATHLTHTrainTodayAgendaPolicy.remainingSessions(
            sessions, primaryWorkoutID: primary.id, completedIDs: [],
            hasPlan: false, hasActiveWorkout: true
        )
        XCTAssertEqual(noPlan.count, 2)

        // After all planned sessions finish, the completed-day card is shown.
        // Their details remain reachable from the secondary agenda.
        let completed = ATHLTHTrainTodayAgendaPolicy.remainingSessions(
            sessions, primaryWorkoutID: primary.id,
            completedIDs: [primary.id, extra.id],
            hasPlan: true, hasActiveWorkout: false
        )
        XCTAssertEqual(completed.count, 2)
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
        let plannedWorkout = PlannedSession(
            id: UUID(), title: "Styrke – Hele kroppen", kind: .strength,
            scheduledStart: .now, durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        let scenarios: [(TrainingPlan?, [PlannedSession])] = [
            (nil, []),
            (plan, []),
            (plan, [plannedWorkout])
        ]
        // Quick Train's friend strip requires the same social environment
        // injected by the production tab root.
        let social = SocialStore()
        for width in [320.0, 375.0, 430.0] {
            for (currentPlan, daySessions) in scenarios {
                for hasActiveWorkout in [false, true] {
                let today = ATHLTHTrainTodayPremiumView(
                    workoutCatalog: WorkoutTemplateCatalogStore(),
                    plan: currentPlan,
                    sessions: daySessions,
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
                    latestHealthWeightKilograms: nil,
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
