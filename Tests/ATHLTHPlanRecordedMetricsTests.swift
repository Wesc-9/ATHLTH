import Foundation
import HealthKit
import XCTest
@testable import ATHLTH

final class ATHLTHPlanRecordedMetricsTests: XCTestCase {
    @MainActor
    private func makeStore() -> (AppSessionStore, UserDefaults, String) {
        let suite = "ATHLTHPlanRecordedMetricsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppSessionStore(defaults: defaults), defaults, suite)
    }

    private func session(
        kind: WorkoutKind,
        plannedMinutes: Int?,
        distanceKm: Double? = nil
    ) -> PlannedSession {
        PlannedSession(
            id: UUID(), title: "Training", kind: kind,
            scheduledStart: nil, durationMinutes: plannedMinutes,
            targetDistanceKilometers: distanceKm,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: nil
        )
    }

    private func run(at date: Date, minutes: Double, distanceKm: Double? = nil)
        -> WorkoutSummary {
        WorkoutSummary(workout: HKWorkout(
            activityType: .running,
            start: date,
            end: date.addingTimeInterval(minutes * 60),
            duration: minutes * 60,
            totalEnergyBurned: nil,
            totalDistance: distanceKm.map {
                HKQuantity(unit: .meter(), doubleValue: $0 * 1000)
            },
            metadata: nil
        ))
    }

    private func strengthLog(
        sessionID: UUID?, start: Date,
        minutes: Double, finished: Bool = true
    ) -> StrengthWorkoutLog {
        StrengthWorkoutLog(
            id: UUID(), plannedSessionID: sessionID,
            watchSessionID: nil, captureDevice: .iPhone,
            trackingMode: .advanced, title: "Strength",
            startedAt: start,
            endedAt: finished ? start.addingTimeInterval(minutes * 60) : nil,
            exercises: [],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil, duration: nil,
                activeCalories: nil, averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
    }

    @MainActor
    func testUnlinkedRunAndManualCompletionHaveNoInventedMetrics() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Evidence", summary: "", weekCount: 1, startDate: start
        ))
        let target = session(kind: .running, plannedMinutes: 40, distanceKm: 5)
        store.addSession(target, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let activity = run(at: start, minutes: 45, distanceKm: 6)
        var report = ATHLTHPlanRecordedMetrics.inspect(
            plan: saved, store: store,
            healthWorkouts: [activity], strengthHistory: []
        )
        XCTAssertFalse(report.hasComparisons)

        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: target.id, completed: true
        )
        report = ATHLTHPlanRecordedMetrics.inspect(
            plan: saved, store: store,
            healthWorkouts: [activity], strengthHistory: []
        )
        XCTAssertFalse(report.hasComparisons)
        XCTAssertEqual(report.runningMinutes.sessions, 0)

        XCTAssertTrue(store.linkHealthWorkout(
            activity, toPlan: plan.id, sessionID: target.id
        ))
        report = ATHLTHPlanRecordedMetrics.inspect(
            plan: saved, store: store,
            healthWorkouts: [activity], strengthHistory: []
        )
        XCTAssertEqual(report.runningMinutes.sessions, 1)
        XCTAssertEqual(report.runningMinutes.planned, 40, accuracy: 0.01)
        XCTAssertEqual(report.runningMinutes.actual, 45, accuracy: 0.01)
        XCTAssertEqual(report.runningKilometers.sessions, 1)
        XCTAssertEqual(report.runningKilometers.planned, 5, accuracy: 0.01)
        XCTAssertEqual(report.runningKilometers.actual, 6, accuracy: 0.01)

        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: target.id, skipped: true
        )
        report = ATHLTHPlanRecordedMetrics.inspect(
            plan: saved, store: store,
            healthWorkouts: [activity], strengthHistory: []
        )
        XCTAssertFalse(report.hasComparisons)
    }

    @MainActor
    func testCompletedStrengthLogSupportsPairedTimeButNotRunningDistance()
        throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Strength evidence", summary: "", weekCount: 1,
            startDate: start
        ))
        let target = session(kind: .strength, plannedMinutes: 60)
        store.addSession(target, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let completed = strengthLog(
            sessionID: target.id, start: start, minutes: 50
        )
        let report = ATHLTHPlanRecordedMetrics.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [completed]
        )
        XCTAssertEqual(report.strengthMinutes.sessions, 1)
        XCTAssertEqual(report.strengthMinutes.planned, 60, accuracy: 0.01)
        XCTAssertEqual(report.strengthMinutes.actual, 50, accuracy: 0.01)
        XCTAssertEqual(report.runningKilometers.sessions, 0)
        XCTAssertEqual(report.runningMinutes.sessions, 0)
    }

    @MainActor
    func testMissingTargetsOrMeasurementsDoNotBecomeZeroTotals() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Unknown values", summary: "", weekCount: 1,
            startDate: start
        ))
        let target = session(kind: .running, plannedMinutes: nil, distanceKm: 4)
        store.addSession(target, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let activity = run(at: start, minutes: 25)
        XCTAssertTrue(store.linkHealthWorkout(
            activity, toPlan: plan.id, sessionID: target.id
        ))
        let report = ATHLTHPlanRecordedMetrics.inspect(
            plan: saved, store: store,
            healthWorkouts: [activity], strengthHistory: []
        )
        XCTAssertFalse(report.hasComparisons)
        XCTAssertEqual(report.runningMinutes.sessions, 0)
        XCTAssertEqual(report.runningKilometers.sessions, 0)
    }

    @MainActor
    func testRepeatedEvidenceDoesNotDoubleCountSession() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Single evidence", summary: "", weekCount: 1,
            startDate: start
        ))
        let target = session(kind: .strength, plannedMinutes: 40)
        store.addSession(target, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let a = strengthLog(sessionID: target.id, start: start, minutes: 41)
        let b = strengthLog(sessionID: target.id,
                            start: start.addingTimeInterval(3600),
                            minutes: 42)
        let report = ATHLTHPlanRecordedMetrics.inspect(
            plan: saved, store: store, healthWorkouts: [],
            strengthHistory: [a, b]
        )
        XCTAssertEqual(report.strengthMinutes.sessions, 1)
        XCTAssertEqual(report.strengthMinutes.actual, 42, accuracy: 0.01)
    }
}
