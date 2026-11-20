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

        // Train > Plan and Train > I dag must agree with the recorded
        // structured workout, even when there is no HealthKit workout yet.
        let before = store.trainingPlanProgress(
            savedPlan,
            healthWorkouts: [],
            strengthHistory: [],
            structuredHistory: [],
            referenceDate: today
        )
        XCTAssertEqual(before.completedSessions, 0)

        let partial = StructuredWorkoutCompletion(
            id: UUID(), workoutTemplateID: nil,
            sourceWorkoutID: prepared.id, title: prepared.title,
            category: "strength", startedAt: today,
            endedAt: today.addingTimeInterval(300),
            completedBlockCount: 1, totalBlockCount: 2,
            sourcePlanID: plan.id
        )
        XCTAssertTrue(prepared.isStructuredWorkout)
        // Only complete workouts count in plan progress or speed history.
        // Saving one block must never award a completed session.
        let afterPartial = store.trainingPlanProgress(
            savedPlan,
            healthWorkouts: [],
            strengthHistory: [],
            structuredHistory: [partial],
            referenceDate: today
        )
        XCTAssertEqual(afterPartial.completedSessions, 0)

        let completion = StructuredWorkoutCompletion(
            id: UUID(), workoutTemplateID: nil,
            sourceWorkoutID: prepared.id, title: prepared.title,
            category: "strength", startedAt: today,
            endedAt: today.addingTimeInterval(600),
            completedBlockCount: 2, totalBlockCount: 2,
            sourcePlanID: plan.id
        )
        let after = store.trainingPlanProgress(
            savedPlan,
            healthWorkouts: [],
            strengthHistory: [],
            structuredHistory: [completion],
            referenceDate: today
        )
        XCTAssertEqual(after.completedSessions, 1)
        XCTAssertEqual(after.missed.count, 0)

        let unrelated = StructuredWorkoutCompletion(
            id: UUID(), workoutTemplateID: nil,
            sourceWorkoutID: prepared.id, title: prepared.title,
            category: "strength", startedAt: today,
            endedAt: today.addingTimeInterval(600),
            completedBlockCount: 2, totalBlockCount: 2,
            sourcePlanID: UUID()
        )
        let unrelatedProgress = store.trainingPlanProgress(
            savedPlan, healthWorkouts: [], strengthHistory: [],
            structuredHistory: [unrelated], referenceDate: today
        )
        XCTAssertEqual(unrelatedProgress.completedSessions, 0)

        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: prepared.id, skipped: true
        )
        let skipped = store.trainingPlanProgress(
            savedPlan, healthWorkouts: [], strengthHistory: [],
            structuredHistory: [completion], referenceDate: today
        )
        XCTAssertEqual(skipped.completedSessions, 0)
        XCTAssertEqual(skipped.skippedSessions, 1)
    }

    @MainActor
    func testStructuredCompletionRecoveryIsIdempotentForSameRecordedStart() throws {
        let suite = "ATHLTHStructuredCompletionOnce.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = UUID()
        let source = UUID()
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        func completion(_ receipt: UUID, at began: Date) -> StructuredWorkoutCompletion {
            StructuredWorkoutCompletion(
                id: receipt, workoutTemplateID: source,
                sourceWorkoutID: source, title: "Mixed session",
                category: "hybrid", startedAt: began,
                endedAt: began.addingTimeInterval(900),
                completedBlockCount: 3, totalBlockCount: 3
            )
        }
        let original = completion(UUID(), at: start)
        XCTAssertTrue(StructuredWorkoutCompletionStore.save(
            original, userID: account, defaults: defaults
        ))
        let replay = completion(UUID(), at: start)
        XCTAssertTrue(StructuredWorkoutCompletionStore.save(
            replay, userID: account, defaults: defaults
        ))
        let once = AccountLocalStorage.read(
            [StructuredWorkoutCompletion].self, name: "structuredWorkoutHistory",
            userID: account, defaults: defaults
        )
        XCTAssertEqual(once?.count, 1)
        XCTAssertEqual(once?.first?.id, original.id)

        // Repeating an unlinked library workout starts a distinct session,
        // even when the user chooses the same saved exercise recipe.
        let later = completion(UUID(), at: start.addingTimeInterval(3_600))
        XCTAssertTrue(StructuredWorkoutCompletionStore.save(
            later, userID: account, defaults: defaults
        ))
        let twice = AccountLocalStorage.read(
            [StructuredWorkoutCompletion].self, name: "structuredWorkoutHistory",
            userID: account, defaults: defaults
        )
        XCTAssertEqual(twice?.count, 2)
        XCTAssertEqual(Set(twice?.map(\.id) ?? []), [original.id, later.id])
    }

}
