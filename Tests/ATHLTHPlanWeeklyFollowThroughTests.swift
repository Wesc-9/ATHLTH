import Foundation
import HealthKit
import XCTest
@testable import ATHLTH

final class ATHLTHPlanWeeklyFollowThroughTests: XCTestCase {
    @MainActor
    private func prepared(weekCount: Int = 2) throws
      -> (AppSessionStore, UserDefaults, String, TrainingPlan) {
        let suite = "ATHLTHPlanWeeklyFollowThroughTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = AppSessionStore(defaults: defaults)
        let start = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Follow-through", summary: "",
            weekCount: weekCount, startDate: start
        ))
        return (store, defaults, suite, plan)
    }

    private func workout() -> PlannedSession {
        PlannedSession(
            id: UUID(), title: "Run", kind: .running,
            scheduledStart: nil, durationMinutes: 30,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
    }

    @MainActor
    func testPastRequiresReviewButTodayAndFutureRemainUpcoming() throws {
        let (store, defaults, suite, plan) = try prepared()
        defer { defaults.removePersistentDomain(forName: suite) }
        let older = workout()
        let current = workout()
        let future = workout()
        store.addSession(
            older, toDay: plan.weeks[0].days[0].id, inPlan: plan.id
        )
        store.addSession(
            current, toDay: plan.weeks[0].days[1].id, inPlan: plan.id
        )
        store.addSession(
            future, toDay: plan.weeks[1].days[0].id, inPlan: plan.id
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let nextDay = Calendar.current.date(
            byAdding: .day, value: 1, to: plan.startDate!
        )!
        let report = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: nextDay
        )
        XCTAssertEqual(report.total, 3)
        XCTAssertEqual(report.needsReview, 1)
        XCTAssertEqual(report.upcoming, 2)
        XCTAssertEqual(report.skipped, 0)
        XCTAssertEqual(report.weeks[0].firstReviewDayID, plan.weeks[0].days[0].id)
        XCTAssertEqual(report.relevantWeeks.first?.number, 1)
    }

    @MainActor
    func testCompletedAndSkippedOverrideCalendarDates() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let completed = workout()
        let skipped = workout()
        let needsReview = workout()
        store.addSession(
            completed, toDay: plan.weeks[0].days[0].id, inPlan: plan.id
        )
        store.addSession(
            skipped, toDay: plan.weeks[0].days[1].id, inPlan: plan.id
        )
        store.addSession(
            needsReview, toDay: plan.weeks[0].days[2].id, inPlan: plan.id
        )
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: completed.id, completed: true
        )
        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: skipped.id, skipped: true
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let future = Calendar.current.date(
            byAdding: .day, value: 4, to: plan.startDate!
        )!
        let result = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: future
        )
        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.completed, 1)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(result.needsReview, 1)
        XCTAssertEqual(result.upcoming, 0)
        XCTAssertEqual(result.pastDated, 3)
        XCTAssertEqual(result.pastConfirmed, 2)
        XCTAssertEqual(result.pastCompleted, 1)
        XCTAssertEqual(result.pastSkipped, 1)
        XCTAssertEqual(result.pastUnreviewed, 1)
        XCTAssertEqual(result.completionPercent, 33)
        XCTAssertEqual(result.accountedPercent, 67)
    }

    @MainActor
    func testFutureOutcomesAreExcludedFromPastCoverage() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let overdue = workout()
        let todayCompleted = workout()
        let futureSkipped = workout()
        store.addSession(overdue, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(todayCompleted, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        store.addSession(futureSkipped, toDay: plan.weeks[0].days[2].id, inPlan: plan.id)
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: todayCompleted.id, completed: true
        )
        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: futureSkipped.id, skipped: true
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let today = Calendar.current.date(byAdding: .day, value: 1, to: plan.startDate!)!
        let report = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: today
        )
        XCTAssertEqual(report.pastDated, 1)
        XCTAssertEqual(report.pastConfirmed, 0)
        XCTAssertEqual(report.pastCompleted, 0)
        XCTAssertEqual(report.completionPercent, 0)
        XCTAssertEqual(report.accountedPercent, 0)
        XCTAssertEqual(report.needsReview, 1)
        XCTAssertEqual(report.completed, 1)
        XCTAssertEqual(report.skipped, 1)
    }

    @MainActor
    func testUnlinkedHealthActivityNeverFakesCompletion() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let run = workout()
        store.addSession(run, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let health = WorkoutSummary(workout: HKWorkout(
            activityType: .running,
            start: plan.startDate!,
            end: plan.startDate!.addingTimeInterval(1200),
            duration: 1200, totalEnergyBurned: nil,
            totalDistance: nil, metadata: nil
        ))
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let tomorrow = Calendar.current.date(
            byAdding: .day, value: 1, to: plan.startDate!
        )!
        let before = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [health],
            strengthHistory: [], referenceDate: tomorrow
        )
        XCTAssertEqual(before.completed, 0)
        XCTAssertEqual(before.needsReview, 1)
        XCTAssertTrue(store.linkHealthWorkout(
            health, toPlan: plan.id, sessionID: run.id
        ))
        let after = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [health],
            strengthHistory: [], referenceDate: tomorrow
        )
        XCTAssertEqual(after.completed, 1)
        XCTAssertEqual(after.needsReview, 0)
    }

    @MainActor
    func testMissingPlanDateIsUnknownNotOverdue() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let run = workout()
        var copy = plan
        copy.startDate = nil
        copy.weeks[0].days[0].sessions = [run]
        let result = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: copy, store: store, healthWorkouts: [],
            strengthHistory: [],
            referenceDate: Date().addingTimeInterval(3600 * 24 * 120)
        )
        XCTAssertEqual(result.unknownDate, 1)
        XCTAssertEqual(result.pastDated, 0)
        XCTAssertNil(result.completionPercent)
        XCTAssertNil(result.accountedPercent)
        XCTAssertEqual(result.pastConfirmed, 0)
        XCTAssertEqual(result.needsReview, 0)
        XCTAssertEqual(result.upcoming, 0)
    }

    @MainActor
    func testTrendRequiresTwoFullyPastWeeks() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 3)
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = workout()
        let second = workout()
        let current = workout()
        store.addSession(first, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(second, toDay: plan.weeks[1].days[0].id, inPlan: plan.id)
        store.addSession(current, toDay: plan.weeks[2].days[0].id, inPlan: plan.id)
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: second.id, completed: true
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let partial = Calendar.current.date(byAdding: .day, value: 7, to: plan.startDate!)!
        let before = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: partial
        )
        XCTAssertNil(before.completedWeekTrend)
        let later = Calendar.current.date(byAdding: .day, value: 14, to: plan.startDate!)!
        let after = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: later
        )
        XCTAssertEqual(after.completedWeekTrend?.previous.number, 1)
        XCTAssertEqual(after.completedWeekTrend?.latest.number, 2)
        XCTAssertEqual(after.completedWeekTrend?.delta, 100)
        XCTAssertEqual(after.completedWeekTrend?.previous.pastUnreviewed, 1)
        XCTAssertEqual(after.completedWeekTrend?.latest.pastCompleted, 1)
        XCTAssertEqual(after.completedWeekTrend?.latest.pastSkipped, 0)
    }

    @MainActor
    func testTrendExcludesCurrentWeekEvenWhenAllItsSessionsAreInThePast() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 3)
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = workout()
        let second = workout()
        store.addSession(first, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(second, toDay: plan.weeks[1].days[0].id, inPlan: plan.id)
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: second.id, completed: true
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let middleOfSecondWeek = Calendar.current.date(
            byAdding: .day, value: 9, to: plan.startDate!
        )!
        let report = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: middleOfSecondWeek
        )
        XCTAssertEqual(report.weeks[1].pastDated, 1)
        XCTAssertFalse(report.weeks[1].isFullyElapsed)
        XCTAssertNil(report.completedWeekTrend)
    }

    @MainActor
    func testReviewSuggestionIsReadOnlyAndRequiresRepeatedEvidence() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = workout()
        let second = workout()
        store.addSession(first, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(second, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 3, to: plan.startDate!)!
        let before = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: tomorrow
        )
        XCTAssertEqual(before.reviewSuggestion, .reviewUnresolved(2))
        XCTAssertEqual(before.needsReview, 2)
        store.setPlanSessionSkipped(planID: plan.id, sessionID: first.id, skipped: true)
        store.setPlanSessionSkipped(planID: plan.id, sessionID: second.id, skipped: true)
        let after = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: tomorrow
        )
        XCTAssertEqual(after.reviewSuggestion, .reviewSkipped(2))
        XCTAssertEqual(after.needsReview, 0)
        XCTAssertEqual(after.pastSkipped, 2)
    }

    @MainActor
    func testSkippedSuggestionTargetsSkippedDayNotUnrelatedDay() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = workout()
        let second = workout()
        store.addSession(first, toDay: plan.weeks[0].days[2].id, inPlan: plan.id)
        store.addSession(second, toDay: plan.weeks[0].days[3].id, inPlan: plan.id)
        store.setPlanSessionSkipped(planID: plan.id, sessionID: first.id, skipped: true)
        store.setPlanSessionSkipped(planID: plan.id, sessionID: second.id, skipped: true)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let later = Calendar.current.date(byAdding: .day, value: 6, to: plan.startDate!)!
        let report = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: later
        )
        XCTAssertEqual(report.reviewSuggestion, .reviewSkipped(2))
        XCTAssertEqual(report.weeks[0].firstSkippedDayID, plan.weeks[0].days[2].id)
        XCTAssertNil(report.weeks[0].firstReviewDayID)
    }

    @MainActor
    func testMovePreviewRejectsOccupiedDestinationAfterPreview() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = workout()
        store.addSession(source, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        XCTAssertTrue(ATHLTHPlanWeeklyFollowThrough.validateMovePreview(
            preview, plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        store.addSession(workout(), toDay: preview.destinationDayID, inPlan: plan.id)
        let changed = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertFalse(ATHLTHPlanWeeklyFollowThrough.validateMovePreview(
            preview, plan: changed, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
    }

    @MainActor
    func testMovePreviewRejectsCompletedSessionAfterPreview() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = workout()
        store.addSession(source, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: source.id, completed: true
        )
        XCTAssertFalse(ATHLTHPlanWeeklyFollowThrough.validateMovePreview(
            preview, plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
    }

    @MainActor
    func testMovePreviewRejectsDuplicatedSessionIdentity() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = workout()
        var duplicate = plan
        duplicate.weeks[0].days[0].sessions = [source]
        duplicate.weeks[0].days[2].sessions = [source]
        XCTAssertNil(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: duplicate, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        let preview = ATHLTHPlanWeeklyFollowThrough.MovePreview(
            weekID: duplicate.weeks[0].id,
            sessionID: source.id,
            sourceDayID: duplicate.weeks[0].days[0].id,
            destinationDayID: duplicate.weeks[0].days[1].id,
            sourceDayIndex: 1,
            destinationDayIndex: 2
        )
        XCTAssertFalse(ATHLTHPlanWeeklyFollowThrough.validateMovePreview(
            preview, plan: duplicate, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
    }

    @MainActor
    func testApprovedMovePersistsWorkoutAtTargetAndIncrementsVersion() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let sourceWorkout = workout()
        store.addSession(sourceWorkout, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        XCTAssertTrue(ATHLTHPlanWeeklyFollowThrough.applyApprovedMove(
            preview, expectedVersion: saved.version, store: store, planID: plan.id,
            healthWorkouts: [], strengthHistory: [], referenceDate: plan.startDate!
        ))
        let updated = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(updated.version, saved.version + 1)
        let source = try XCTUnwrap(updated.weeks[0].days.first(where: {
            $0.id == preview.sourceDayID
        }))
        let destination = try XCTUnwrap(updated.weeks[0].days.first(where: {
            $0.id == preview.destinationDayID
        }))
        XCTAssertFalse(source.sessions.contains(where: { $0.id == sourceWorkout.id }))
        XCTAssertEqual(destination.sessions.filter { $0.id == sourceWorkout.id }.count, 1)
        XCTAssertEqual(destination.sessions.first?.title, sourceWorkout.title)
        XCTAssertNotNil(destination.sessions.first?.scheduledStart)
    }

    @MainActor
    func testApprovedMoveRejectsStaleVersionWithoutChangingPlan() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let sourceWorkout = workout()
        store.addSession(sourceWorkout, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        store.addSession(workout(), toDay: plan.weeks[0].days[6].id, inPlan: plan.id)
        let changed = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertFalse(ATHLTHPlanWeeklyFollowThrough.applyApprovedMove(
            preview, expectedVersion: saved.version, store: store, planID: plan.id,
            healthWorkouts: [], strengthHistory: [], referenceDate: plan.startDate!
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(after.version, changed.version)
        XCTAssertTrue(after.weeks[0].days[0].sessions.contains(where: { $0.id == sourceWorkout.id }))
    }

    @MainActor
    func testApprovedMoveRejectsOccupiedTargetWithoutChangingPlan() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let sourceWorkout = workout()
        store.addSession(sourceWorkout, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        store.addSession(workout(), toDay: preview.destinationDayID, inPlan: plan.id)
        let changed = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertFalse(ATHLTHPlanWeeklyFollowThrough.applyApprovedMove(
            preview, expectedVersion: changed.version, store: store, planID: plan.id,
            healthWorkouts: [], strengthHistory: [], referenceDate: plan.startDate!
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(after.version, changed.version)
        XCTAssertTrue(after.weeks[0].days[0].sessions.contains(where: { $0.id == sourceWorkout.id }))
    }

    @MainActor
    func testMovePreviewPrefersDayWithFewerAdjacentWorkouts() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.addSession(workout(), toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[2].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        // Day 4 is free but borders the day 3 workout.
        // Day 5 has no adjacent workouts and is preferred.
        XCTAssertEqual(preview.sourceDayIndex, 1)
        XCTAssertEqual(preview.destinationDayIndex, 5)
    }

    @MainActor
    func testMovePreviewAccountsForWorkoutAcrossWeekBoundary() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 2)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.addSession(workout(), toDay: plan.weeks[1].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[1].days[2].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[6].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        // First eligible source is the final day of week 1, so it has
        // no later destination in that week. Week 2 day 1 is bordered
        // by week 1 day 7 and week 2 day 2, and should move to day 5.
        XCTAssertEqual(preview.weekID, plan.weeks[1].id)
        XCTAssertEqual(preview.sourceDayIndex, 1)
        XCTAssertEqual(preview.destinationDayIndex, 5)
    }

    @MainActor
    func testMovePreviewDoesNotProposeChangeWhenSpacingCannotImprove() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.addSession(workout(), toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertNil(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
    }

    @MainActor
    func testMovePreviewSuggestsOnlyStrictlyImprovedSpacing() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.addSession(workout(), toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        XCTAssertEqual(preview.sourceDayIndex, 1)
        XCTAssertEqual(preview.destinationDayIndex, 4)
    }

    @MainActor
    func testApprovedMoveCannotBeAppliedTwice() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.addSession(workout(), toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        XCTAssertTrue(ATHLTHPlanWeeklyFollowThrough.applyApprovedMove(
            preview, expectedVersion: saved.version, store: store, planID: plan.id,
            healthWorkouts: [], strengthHistory: [], referenceDate: plan.startDate!
        ))
        let moved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertFalse(ATHLTHPlanWeeklyFollowThrough.applyApprovedMove(
            preview, expectedVersion: saved.version, store: store, planID: plan.id,
            healthWorkouts: [], strengthHistory: [], referenceDate: plan.startDate!
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(after.version, moved.version)
    }

    @MainActor
    func testApprovedMoveRejectsSkippedWorkoutWithoutChangingPlan() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let sourceWorkout = workout()
        store.addSession(sourceWorkout, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: sourceWorkout.id, skipped: true
        )
        XCTAssertFalse(ATHLTHPlanWeeklyFollowThrough.applyApprovedMove(
            preview, expectedVersion: saved.version, store: store, planID: plan.id,
            healthWorkouts: [], strengthHistory: [], referenceDate: plan.startDate!
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(after.version, saved.version)
        XCTAssertTrue(after.weeks[0].days[0].sessions.contains(where: {
            $0.id == sourceWorkout.id
        }))
    }

    @MainActor
    func testApprovedMoveRejectsCompletedWorkoutWithoutChangingPlan() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let sourceWorkout = workout()
        store.addSession(sourceWorkout, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: sourceWorkout.id, completed: true
        )
        XCTAssertFalse(ATHLTHPlanWeeklyFollowThrough.applyApprovedMove(
            preview, expectedVersion: saved.version, store: store, planID: plan.id,
            healthWorkouts: [], strengthHistory: [], referenceDate: plan.startDate!
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(after.version, saved.version)
        XCTAssertTrue(after.weeks[0].days[0].sessions.contains(where: {
            $0.id == sourceWorkout.id
        }))
    }

    @MainActor
    func testPreviewRejectsMoveAfterSpacingBenefitDisappears() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.addSession(workout(), toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        // A newly planned workout next to the destination makes this
        // proposal no longer the best available improvement.
        let neighborIndex = preview.destinationDayIndex
        guard neighborIndex < 7 else { return XCTFail("Expected earlier target") }
        store.addSession(workout(), toDay: plan.weeks[0].days[neighborIndex].id, inPlan: plan.id)
        let changed = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertFalse(ATHLTHPlanWeeklyFollowThrough.validateMovePreview(
            preview, plan: changed, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
    }

    @MainActor
    func testSkippedNeighborDoesNotTriggerUnnecessaryMove() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = workout()
        let neighbor = workout()
        store.addSession(source, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(neighbor, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: neighbor.id, skipped: true
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertNil(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
    }

    @MainActor
    func testCompletedNeighborDoesNotTriggerUnnecessaryMove() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = workout()
        let neighbor = workout()
        store.addSession(source, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(neighbor, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: neighbor.id, completed: true
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertNil(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
    }

    @MainActor
    func testSkippedNeighborAcrossWeekBoundaryDoesNotCreatePressure() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 2)
        defer { defaults.removePersistentDomain(forName: suite) }
        let neighbor = workout()
        store.addSession(neighbor, toDay: plan.weeks[0].days[6].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[1].days[0].id, inPlan: plan.id)
        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: neighbor.id, skipped: true
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertNil(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
    }

    @MainActor
    func testCompletedNeighborAcrossWeekBoundaryDoesNotCreatePressure() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 2)
        defer { defaults.removePersistentDomain(forName: suite) }
        let neighbor = workout()
        store.addSession(neighbor, toDay: plan.weeks[0].days[6].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[1].days[0].id, inPlan: plan.id)
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: neighbor.id, completed: true
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertNil(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
    }

    @MainActor
    func testMoveAvoidsDestinationAdjacentToSkippedWorkout() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let skipped = workout()
        store.addSession(workout(), toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        store.addSession(skipped, toDay: plan.weeks[0].days[4].id, inPlan: plan.id)
        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: skipped.id, skipped: true
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        // Day 4 borders skipped day 5, and day 6 borders it too.
        // Day 7 is the earliest destination with no occupied neighbors.
        XCTAssertEqual(preview.sourceDayIndex, 1)
        XCTAssertEqual(preview.destinationDayIndex, 7)
    }

    @MainActor
    func testMoveAvoidsDestinationAdjacentToCompletedWorkout() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let completed = workout()
        store.addSession(workout(), toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        store.addSession(completed, toDay: plan.weeks[0].days[4].id, inPlan: plan.id)
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: completed.id, completed: true
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        XCTAssertEqual(preview.sourceDayIndex, 1)
        XCTAssertEqual(preview.destinationDayIndex, 7)
    }

    @MainActor
    func testMoveAvoidsDestinationAdjacentToNextWeekWorkout() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 2)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.addSession(workout(), toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[0].days[3].id, inPlan: plan.id)
        store.addSession(workout(), toDay: plan.weeks[1].days[0].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = try XCTUnwrap(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
        // Day 7 of week 1 borders the occupied first day of week 2.
        // Day 6 has no occupied neighbors and is the safer destination.
        XCTAssertEqual(preview.weekID, plan.weeks[0].id)
        XCTAssertEqual(preview.sourceDayIndex, 1)
        XCTAssertEqual(preview.destinationDayIndex, 6)
    }

    @MainActor
    func testDuplicateIdentitiesAreCountedOnlyOnce() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let workout = workout()
        var copy = plan
        copy.weeks[0].days[0].sessions = [workout]
        copy.weeks[0].days[1].sessions = [workout]
        let result = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: copy, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        )
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.upcoming, 1)
    }
}
