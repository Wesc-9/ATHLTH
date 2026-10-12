import Foundation
import HealthKit
import XCTest
@testable import ATHLTH

final class ATHLTHPlanReviewEligibilityTests: XCTestCase {
    @MainActor
    private func store() -> (AppSessionStore, UserDefaults, String) {
        let suite = "ATHLTHPlanReviewEligibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppSessionStore(defaults: defaults), defaults, suite)
    }

    private func workout(_ minutes: Int? = nil) -> PlannedSession {
        PlannedSession(
            id: UUID(), title: "Run", kind: .running,
            scheduledStart: nil, durationMinutes: minutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
    }

    @MainActor
    func testManualCompletionAndSkippedWorkoutsAreNotSuggested() throws {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Eligibility", summary: "",
            weekCount: 1, startDate: start
        ))
        let eligible = workout()
        let finished = workout()
        let skipped = workout()
        store.addSession(eligible, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(finished, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        store.addSession(skipped, toDay: plan.weeks[0].days[2].id, inPlan: plan.id)
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: finished.id, completed: true
        )
        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: skipped.id, skipped: true
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let editable = ATHLTHPlanReviewEligibility.editableIDs(
            in: saved, store: store,
            healthWorkouts: [], strengthHistory: [], referenceDate: start
        )
        XCTAssertTrue(editable.contains(eligible.id))
        XCTAssertFalse(editable.contains(finished.id))
        XCTAssertFalse(editable.contains(skipped.id))
        let suggestion = try XCTUnwrap(
            ATHLTHPlanReviewAdvisor.inspect(
                saved, referenceDate: start
            ).first(where: {
                $0.kind == .missingDuration &&
                $0.dayID == plan.weeks[0].days[1].id
            })
        )
        XCTAssertFalse(ATHLTHPlanReviewEligibility.isRelevant(
            suggestion, in: saved, editableIDs: editable
        ))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let later = ATHLTHPlanReviewEligibility.editableIDs(
            in: saved, store: store,
            healthWorkouts: [], strengthHistory: [], referenceDate: tomorrow
        )
        XCTAssertFalse(later.contains(eligible.id))
    }

    @MainActor
    func testLinkedHealthWorkoutPreventsFutureReview() throws {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Linked", summary: "", weekCount: 1, startDate: start
        ))
        let run = workout()
        store.addSession(run, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let health = WorkoutSummary(workout: HKWorkout(
            activityType: .running, start: start,
            end: start.addingTimeInterval(1800), duration: 1800,
            totalEnergyBurned: nil, totalDistance: nil, metadata: nil
        ))
        XCTAssertTrue(store.linkHealthWorkout(
            health, toPlan: plan.id, sessionID: run.id
        ))
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let editable = ATHLTHPlanReviewEligibility.editableIDs(
            in: saved, store: store,
            healthWorkouts: [health], strengthHistory: [],
            referenceDate: start
        )
        XCTAssertFalse(editable.contains(run.id))
    }

    @MainActor
    func testMissingStartDateIsNeverEditable() throws {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "No date", summary: "", weekCount: 1, startDate: start
        ))
        var withoutDate = plan
        withoutDate.startDate = nil
        XCTAssertTrue(ATHLTHPlanReviewEligibility.editableIDs(
            in: withoutDate, store: store,
            healthWorkouts: [], strengthHistory: []
        ).isEmpty)
    }
}
