import Foundation
import XCTest
@testable import ATHLTH

/// Verifies the real Plan Studio persistence path used after the detailed
/// composer closes. This must never create a duplicate workout execution.
final class ATHLTHStructuredWorkoutPlanIntegrationTests: XCTestCase {
    @MainActor
    func testStructuredStrengthWithRestPersistsAndAppearsToday() throws {
        let suite = "ATHLTHStructuredWorkoutPlanIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Detailed workouts", summary: "", weekCount: 1,
            startDate: today
        ))
        let dayID = try XCTUnwrap(plan.weeks.first?.days.first?.id)

        let exercise = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Knebøy",
            exerciseSlug: "squat", distanceMeters: nil,
            repetitions: 10, durationSeconds: nil,
            targetWeightKilograms: 40, loadNote: nil, notes: nil,
            phase: .main, setCount: 3, restBetweenSetsSeconds: 90
        )
        let cooldown = WorkoutTemplateBlock(
            sequence: 2, kind: .rest, title: "Pause",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 60, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .recovery
        )
        var prepared = PlannedSession(
            id: UUID(), title: "Styrke med pauser", kind: .strength,
            scheduledStart: nil, durationMinutes: 10,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        prepared.workoutBlocks = [exercise, cooldown]
        prepared.workoutCategory = "strength"

        XCTAssertTrue(store.savePlanStudioWorkout(
            prepared, inPlan: plan.id, dayID: dayID,
            editingWorkoutID: nil, expectedPlanVersion: plan.version,
            healthWorkouts: [], strengthHistory: []
        ))
        let savedPlan = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let scheduled = ATHLTHTrainingPlanSchedule.sessions(
            in: savedPlan, on: today
        )
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled.first?.id, prepared.id)
        XCTAssertEqual(scheduled.first?.resolvedWorkoutBlocks, [exercise, cooldown])
        XCTAssertTrue(try XCTUnwrap(scheduled.first).exercises.isEmpty)
        XCTAssertEqual(scheduled.first?.resolvedWorkoutBlocks.expandedForExecution()
            .filter { $0.kind == .rest }.count, 3)
        // Two between-set recoveries plus one explicit pause.
    }
}
