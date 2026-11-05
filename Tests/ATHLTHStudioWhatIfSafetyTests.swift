import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHStudioWhatIfSafetyTests: XCTestCase {
    @MainActor
    func testSkipIsExplicitAndCanBeUndoneWithoutDeletingWorkout() throws {
        let suite = "ATHLTHStudioWhatIfSafetyTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AppSessionStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: .now)
        let plan = try XCTUnwrap(session.createTrainingPlan(
            title: "What if", summary: "", weekCount: 2,
            startDate: today
        ))
        let planned = PlannedSession(
            id: UUID(),
            title: "Tempo run",
            kind: .running,
            scheduledStart: nil,
            durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
        session.addSession(
            planned, toDay: plan.weeks[0].days[0].id,
            inPlan: plan.id
        )
        XCTAssertFalse(session.isPlanSessionSkipped(
            planID: plan.id, sessionID: planned.id
        ))
        session.setPlanSessionSkipped(
            planID: plan.id, sessionID: planned.id, skipped: true
        )
        XCTAssertTrue(session.isPlanSessionSkipped(
            planID: plan.id, sessionID: planned.id
        ))
        XCTAssertNotNil(session.trainingPlan(withID: plan.id)?
            .weeks[0].days[0].sessions.first(where: {
                $0.id == planned.id
            }))
        session.setPlanSessionSkipped(
            planID: plan.id, sessionID: planned.id, skipped: false
        )
        XCTAssertFalse(session.isPlanSessionSkipped(
            planID: plan.id, sessionID: planned.id
        ))
    }

    @MainActor
    func testNoWhatIfMoveToPastOrOldPlanVersion() throws {
        let suite = "ATHLTHStudioWhatIfMove." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AppSessionStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: .now)
        let plan = try XCTUnwrap(session.createTrainingPlan(
            title: "Protected", summary: "", weekCount: 2,
            startDate: today
        ))
        let workout = PlannedSession(
            id: UUID(),
            title: "Easy run",
            kind: .running,
            scheduledStart: nil,
            durationMinutes: 30,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
        session.addSession(workout, toDay: plan.weeks[0].days[0].id,
                           inPlan: plan.id)
        let current = try XCTUnwrap(session.trainingPlan(withID: plan.id))
        let yesterday = try XCTUnwrap(Calendar.current.date(
            byAdding: .day, value: -1, to: today
        ))
        XCTAssertFalse(session.movePlanStudioWorkout(
            planID: plan.id,
            workoutID: workout.id,
            targetDate: yesterday,
            expectedVersion: current.version,
            healthWorkouts: [],
            strengthHistory: []
        ))
        let nextWeek = try XCTUnwrap(Calendar.current.date(
            byAdding: .day, value: 7, to: today
        ))
        XCTAssertFalse(session.movePlanStudioWorkout(
            planID: plan.id,
            workoutID: workout.id,
            targetDate: nextWeek,
            expectedVersion: current.version - 1,
            healthWorkouts: [],
            strengthHistory: []
        ))
        XCTAssertEqual(
            session.trainingPlan(withID: plan.id)?
                .weeks[0].days[0].sessions.first?.id,
            workout.id
        )
    }
}
