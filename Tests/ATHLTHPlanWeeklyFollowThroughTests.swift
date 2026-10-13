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
    func testExplicitlyTimedWorkoutIsNeverSuggestedForMoving() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        var timed = workout()
        timed.scheduledStart = Calendar.current.date(
            byAdding: .hour, value: 18, to: plan.startDate!
        )
        let flexible = workout()
        store.addSession(timed, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(flexible, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let preview = ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        )
        // Another flexible workout may still be eligible for a move.
        // The fixed-time workout must never be the suggested source.
        XCTAssertNotEqual(preview?.sessionID, timed.id)
        if let preview {
            XCTAssertEqual(preview.sessionID, flexible.id)
        }
    }

    @MainActor
    func testMovePreviewNeverSelectsPastWorkout() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let past = workout()
        let future = workout()
        store.addSession(past, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(future, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let nextDay = try XCTUnwrap(Calendar.current.date(
            byAdding: .day, value: 1, to: plan.startDate!
        ))
        let preview = ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: nextDay
        )
        // A future session may still be suggested; the past one may not.
        XCTAssertNotEqual(preview?.sessionID, past.id)
        if let preview {
            XCTAssertEqual(preview.sessionID, future.id)
        }
    }

    @MainActor
    func testMovePreviewRejectsDuplicateCalendarDayIndexes() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        var malformed = plan
        // Duplicate the whole day instead of mutating a potentially immutable
        // dayIndex property; this also reproduces a duplicated day identity.
        malformed.weeks[0].days[2] = malformed.weeks[0].days[1]
        malformed.weeks[0].days[0].sessions = [workout()]
        malformed.weeks[0].days[1].sessions = [workout()]
        XCTAssertNil(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: malformed, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
    }

    @MainActor
    func testMovePreviewRejectsDuplicateDayIdentityAcrossWeeks() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 2)
        defer { defaults.removePersistentDomain(forName: suite) }
        var malformed = plan
        // Keep the seven day indexes intact while duplicating a UUID.
        malformed.weeks[1].days[0] = malformed.weeks[0].days[0]
        malformed.weeks[0].days[0].sessions = [workout()]
        malformed.weeks[0].days[1].sessions = [workout()]
        XCTAssertNil(ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: malformed, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: plan.startDate!
        ))
    }

    @MainActor
    func testWeeklyLoadSummarySeparatesWeeksAndFlagsConsecutiveLongDays() throws {
        let (_, defaults, suite, plan) = try prepared(weekCount: 2)
        defer { defaults.removePersistentDomain(forName: suite) }
        var modified = plan
        var first = workout()
        first.durationMinutes = 65
        var second = workout()
        second.durationMinutes = 70
        var third = workout()
        third.durationMinutes = 25
        modified.weeks[0].days[0].sessions = [first]
        modified.weeks[0].days[1].sessions = [second]
        modified.weeks[1].days[0].sessions = [third]
        let weeks = ATHLTHPlanWeeklyFollowThrough.weeklyLoadSummaries(plan: modified)
        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0].plannedMinutes, 135)
        XCTAssertEqual(weeks[0].activeDays, 2)
        XCTAssertEqual(weeks[0].longDays, 2)
        XCTAssertEqual(weeks[0].adjacentLongDayPairs, 1)
        XCTAssertEqual(weeks[1].plannedMinutes, 25)
        XCTAssertEqual(weeks[1].adjacentLongDayPairs, 0)
    }

    @MainActor
    func testWeeklyVolumeChangeUsesPreviousWeekAndHandlesZeroBaseline() throws {
        let (_, defaults, suite, plan) = try prepared(weekCount: 3)
        defer { defaults.removePersistentDomain(forName: suite) }
        var modified = plan
        var first = workout()
        first.durationMinutes = 100
        var second = workout()
        second.durationMinutes = 150
        modified.weeks[1].days[0].sessions = [first]
        modified.weeks[2].days[0].sessions = [second]
        let changes = ATHLTHPlanWeeklyFollowThrough.weeklyVolumeChanges(plan: modified)
        XCTAssertEqual(changes.count, 2)
        XCTAssertNil(changes[0].changePercent)
        XCTAssertEqual(changes[1].changePercent, 50)
        XCTAssertEqual(changes[1].previousMinutes, 100)
        XCTAssertEqual(changes[1].currentMinutes, 150)
    }

    @MainActor
    func testEffortDistributionKeepsUnknownIntensitySeparate() throws {
        let (_, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        var modified = plan
        let easy = workout()
        let unknown = workout()
        modified.weeks[0].days[0].sessions = [easy]
        modified.weeks[0].days[1].sessions = [unknown]
        let result = ATHLTHPlanWeeklyFollowThrough.effortDistribution(
            plan: modified, effortBySessionID: [easy.id: .easy]
        )
        XCTAssertEqual(result.easyMinutes, 30)
        XCTAssertEqual(result.unknownMinutes, 30)
        XCTAssertEqual(result.hardMinutes, 0)
    }

    @MainActor
    func testHardDaysAreDetectedAcrossWeekBoundary() throws {
        let (_, defaults, suite, plan) = try prepared(weekCount: 2)
        defer { defaults.removePersistentDomain(forName: suite) }
        var modified = plan
        let first = workout()
        let second = workout()
        modified.weeks[0].days[6].sessions = [first]
        modified.weeks[1].days[0].sessions = [second]
        let result = ATHLTHPlanWeeklyFollowThrough.effortDistribution(
            plan: modified,
            effortBySessionID: [first.id: .hard, second.id: .hard]
        )
        XCTAssertEqual(result.hardMinutes, 60)
        XCTAssertEqual(result.adjacentHardDayPairs, 1)
    }

    @MainActor
    func testIntensityPersistsAcrossReadsAndIgnoresRemovedSessions() throws {
        let (_, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        var modified = plan
        let workoutOne = workout()
        modified.weeks[0].days[0].sessions = [workoutOne]
        ATHLTHPlanWeeklyFollowThrough.saveEfforts(
            [workoutOne.id: .hard], plan: modified, defaults: defaults
        )
        let restored = ATHLTHPlanWeeklyFollowThrough.savedEfforts(
            plan: modified, defaults: defaults
        )
        XCTAssertEqual(restored[workoutOne.id], .hard)
        modified.weeks[0].days[0].sessions = []
        XCTAssertTrue(ATHLTHPlanWeeklyFollowThrough.savedEfforts(
            plan: modified, defaults: defaults
        ).isEmpty)
    }

    @MainActor
    func testWeeklyEffortBreakdownKeepsUnknownAndHardDaysSeparate() throws {
        let (_, defaults, suite, plan) = try prepared(weekCount: 2)
        defer { defaults.removePersistentDomain(forName: suite) }
        var modified = plan
        let hard = workout()
        let unknown = workout()
        modified.weeks[0].days[0].sessions = [hard]
        modified.weeks[0].days[1].sessions = [unknown]
        let result = ATHLTHPlanWeeklyFollowThrough.weeklyEffortSummaries(
            plan: modified, effortBySessionID: [hard.id: .hard]
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].hardMinutes, 30)
        XCTAssertEqual(result[0].unknownMinutes, 30)
        XCTAssertEqual(result[0].hardDays, 1)
        XCTAssertEqual(result[1].hardMinutes, 0)
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

    @MainActor
    func testEffectiveDateUsesExplicitScheduleAcrossWeeks() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 5
        )))
        let moved = try XCTUnwrap(calendar.date(
            byAdding: .day, value: 18, to: start
        ))
        let actual = ATHLTHPlanWeeklyFollowThrough.effectiveDate(
            scheduledStart: moved, planStart: start,
            weekIndex: 0, dayIndex: 1, calendar: calendar
        )
        XCTAssertEqual(actual, moved)
        let original = ATHLTHPlanWeeklyFollowThrough.effectiveDate(
            scheduledStart: nil, planStart: start,
            weekIndex: 0, dayIndex: 1, calendar: calendar
        )
        XCTAssertEqual(original, start)
    }

    @MainActor
    func testEffectiveDateUsesWeekAndDayOffset() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 5
        )))
        let expected = try XCTUnwrap(calendar.date(
            byAdding: .day, value: 9, to: start
        ))
        XCTAssertEqual(ATHLTHPlanWeeklyFollowThrough.effectiveDate(
            scheduledStart: nil, planStart: start,
            weekIndex: 1, dayIndex: 3, calendar: calendar
        ), expected)
    }

    @MainActor
    func testEffectiveDateDoesNotInventDatesForInvalidDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 5
        )))
        for day in [0, -1, 8, 99] {
            XCTAssertNil(ATHLTHPlanWeeklyFollowThrough.effectiveDate(
                scheduledStart: nil, planStart: start,
                weekIndex: 0, dayIndex: day, calendar: calendar
            ))
        }
        XCTAssertNil(ATHLTHPlanWeeklyFollowThrough.effectiveDate(
            scheduledStart: nil, planStart: nil,
            weekIndex: 0, dayIndex: 1, calendar: calendar
        ))
    }

    @MainActor
    func testInspectUsesMovedWorkoutDateRatherThanOriginalDay() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 2)
        defer { defaults.removePersistentDomain(forName: suite) }
        var moved = workout()
        let shifted = try XCTUnwrap(Calendar.current.date(
            byAdding: .day, value: 10, to: plan.startDate!
        ))
        moved.scheduledStart = shifted
        store.addSession(moved, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let reference = try XCTUnwrap(Calendar.current.date(
            byAdding: .day, value: 3, to: plan.startDate!
        ))
        let report = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: reference
        )
        XCTAssertEqual(report.upcoming, 1)
        XCTAssertEqual(report.needsReview, 0)
        XCTAssertEqual(report.pastDated, 0)
    }

    @MainActor
    func testMissingPlanAndWorkoutDatesRemainUnscheduled() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        var modified = plan
        modified.startDate = nil
        modified.weeks[0].days[0].sessions = [workout()]
        let report = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: modified, store: store, healthWorkouts: [],
            strengthHistory: []
        )
        XCTAssertEqual(report.total, 1)
        XCTAssertEqual(report.unknownDate, 1)
        XCTAssertEqual(report.needsReview, 0)
        XCTAssertEqual(report.upcoming, 0)
        XCTAssertNil(report.completionPercent)
    }

    @MainActor
    func testSkippedStatusTakesPrecedenceOverManualCompletion() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = workout()
        store.addSession(item, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: item.id, completed: true
        )
        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: item.id, skipped: true
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let reference = try XCTUnwrap(Calendar.current.date(
            byAdding: .day, value: 1, to: plan.startDate!
        ))
        let report = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: reference
        )
        XCTAssertEqual(report.total, 1)
        XCTAssertEqual(report.skipped, 1)
        XCTAssertEqual(report.completed, 0)
        XCTAssertEqual(report.pastConfirmed, 1)
        XCTAssertEqual(report.pastCompleted, 0)
    }

    @MainActor
    func testMovedPastWorkoutNeedsReviewEvenIfOriginalDayIsFuture() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 2)
        defer { defaults.removePersistentDomain(forName: suite) }
        var item = workout()
        item.scheduledStart = plan.startDate
        store.addSession(item, toDay: plan.weeks[1].days[0].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let reference = try XCTUnwrap(Calendar.current.date(
            byAdding: .day, value: 2, to: plan.startDate!
        ))
        let report = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: reference
        )
        XCTAssertEqual(report.total, 1)
        XCTAssertEqual(report.needsReview, 1)
        XCTAssertEqual(report.upcoming, 0)
        XCTAssertEqual(report.weeks[1].needsReview, 1)
        XCTAssertEqual(report.weeks[1].firstReviewDayID, plan.weeks[1].days[0].id)
    }

    @MainActor
    func testWorkoutScheduledEarlierTodayIsStillUpcoming() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        var item = workout()
        item.scheduledStart = try XCTUnwrap(Calendar.current.date(
            byAdding: .hour, value: 6, to: plan.startDate!
        ))
        store.addSession(item, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let reference = try XCTUnwrap(Calendar.current.date(
            byAdding: .hour, value: 20, to: plan.startDate!
        ))
        let report = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: reference
        )
        XCTAssertEqual(report.upcoming, 1)
        XCTAssertEqual(report.needsReview, 0)
        XCTAssertEqual(report.pastDated, 0)
    }

    @MainActor
    func testExplicitDateWorksWithoutPlanStart() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        var modified = plan
        modified.startDate = nil
        var item = workout()
        item.scheduledStart = plan.startDate
        modified.weeks[0].days[0].sessions = [item]
        let reference = try XCTUnwrap(Calendar.current.date(
            byAdding: .day, value: 2, to: plan.startDate!
        ))
        let report = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: modified, store: store, healthWorkouts: [],
            strengthHistory: [], referenceDate: reference
        )
        XCTAssertEqual(report.needsReview, 1)
        XCTAssertEqual(report.unknownDate, 0)
        XCTAssertEqual(report.pastDated, 1)
    }
    @MainActor
    func testSeparatedLongDaysAreNotConsecutive() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        var first = workout()
        first.durationMinutes = 75
        var second = workout()
        second.durationMinutes = 80
        store.addSession(first, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(second, toDay: plan.weeks[0].days[2].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(ATHLTHPlanWeeklyFollowThrough.plannedLoadSummary(plan: saved).consecutiveLongDayPairs, 0)
        XCTAssertEqual(ATHLTHPlanWeeklyFollowThrough.weeklyLoadSummaries(plan: saved)[0].adjacentLongDayPairs, 0)
        XCTAssertEqual(ATHLTHPlanWeeklyFollowThrough.effortDistribution(
            plan: saved, effortBySessionID: [first.id: .hard, second.id: .hard]
        ).adjacentHardDayPairs, 0)
    }

    @MainActor
    func testAdjacentLongAndHardDaysAreCounted() throws {
        let (store, defaults, suite, plan) = try prepared(weekCount: 1)
        defer { defaults.removePersistentDomain(forName: suite) }
        var first = workout()
        first.durationMinutes = 70
        var second = workout()
        second.durationMinutes = 70
        store.addSession(first, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(second, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(ATHLTHPlanWeeklyFollowThrough.plannedLoadSummary(plan: saved).consecutiveLongDayPairs, 1)
        XCTAssertEqual(ATHLTHPlanWeeklyFollowThrough.weeklyLoadSummaries(plan: saved)[0].adjacentLongDayPairs, 1)
        XCTAssertEqual(ATHLTHPlanWeeklyFollowThrough.effortDistribution(
            plan: saved, effortBySessionID: [first.id: .hard, second.id: .hard]
        ).adjacentHardDayPairs, 1)
    }

    @MainActor
    func testEffectiveDateRejectsNegativeWeekIndex() {
        let start = Calendar.current.startOfDay(for: Date())
        XCTAssertNil(ATHLTHPlanWeeklyFollowThrough.effectiveDate(
            scheduledStart: nil, planStart: start, weekIndex: -1, dayIndex: 1
        ))
    }

    @MainActor
    func testExplicitDateRemainsAuthoritativeForInvalidWeekIndex() {
        let explicit = Date()
        XCTAssertEqual(ATHLTHPlanWeeklyFollowThrough.effectiveDate(
            scheduledStart: explicit, planStart: nil, weekIndex: -1, dayIndex: 0
        ), explicit)
    }

    @MainActor
    func testEffectiveDateRejectsOverflowingWeekIndex() {
        XCTAssertNil(ATHLTHPlanWeeklyFollowThrough.effectiveDate(
            scheduledStart: nil, planStart: Date(),
            weekIndex: Int.max, dayIndex: 7
        ))
    }

}
