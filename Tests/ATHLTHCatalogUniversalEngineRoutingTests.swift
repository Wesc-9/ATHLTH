import XCTest
@testable import ATHLTH

/// Every catalog training-plan session must use the same activity profile,
/// ordered recipe and capture admission as a standalone planned workout.
final class ATHLTHCatalogUniversalEngineRoutingTests: XCTestCase {
    private func catalog() -> TrainingPlanCatalogEntry {
        TrainingPlanCatalogEntry(
            id: UUID(),
            slug: "universal-engine-regression",
            title: "Test plan",
            summary: "Exercise recipes",
            category: "hybrid",
            goal: "General fitness",
            level: "All levels",
            durationWeeks: 8,
            sessionsPerWeek: 4,
            workoutPattern: ["walk_run", "mobility", "full_body_a"],
            tags: ["mixed"],
            sortOrder: 1,
            catalogVersion: 2
        )
    }

    func testRunWalkPlanUsesOneMeasuredEnduranceRecorder() throws {
        let workout = ATHLTHCatalogPlanSessionFactory.session(
            entry: catalog(), blueprint: .walkRun, week: 1
        )
        let steps = workout.resolvedWorkoutBlocks
        XCTAssertTrue(steps.contains { $0.cardioActivity == .walking })
        XCTAssertTrue(steps.contains { $0.cardioActivity == .running })
        XCTAssertEqual(workout.kind, .running)
        XCTAssertEqual(workout.workoutCategory, "running")
        XCTAssertEqual(ATHLTHUnifiedWorkout.editorBlocks(from: workout), steps)
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(workout, device: .iPhone),
            .phoneEndurance
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(workout, device: .appleWatch),
            .watchEndurance
        )
    }

    func testMobilityPlanCannotBeMislabeledAsRunning() {
        let workout = ATHLTHCatalogPlanSessionFactory.session(
            entry: catalog(), blueprint: .mobility, week: 1
        )
        XCTAssertEqual(workout.workoutCategory, "mobility")
        XCTAssertEqual(workout.kind, .mobility)
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(workout, device: .iPhone),
            .phoneStructuredManual
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(workout, device: .appleWatch),
            .unavailable
        )
    }

    func testStrengthCatalogPlanKeepsStrengthSportAndExerciseBlocks() {
        let workout = ATHLTHCatalogPlanSessionFactory.session(
            entry: catalog(), blueprint: .fullBodyA, week: 1
        )
        XCTAssertEqual(workout.workoutCategory, "strength")
        XCTAssertEqual(workout.kind, .strength)
        XCTAssertTrue(workout.resolvedWorkoutBlocks.contains { $0.kind == .exercise })
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(workout, device: .iPhone),
            .phoneStructuredManual
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(workout, device: .appleWatch),
            .watchStrength
        )
    }

    func testHybridCatalogRecipeNeverPretendsToBePureRunningOrStrength() {
        let workout = ATHLTHCatalogPlanSessionFactory.session(
            entry: catalog(), blueprint: .hyroxCircuit, week: 1
        )
        XCTAssertEqual(workout.workoutCategory, "hybrid")
        XCTAssertEqual(workout.kind, .custom)
        XCTAssertTrue(ATHLTHHybridWorkoutLaunchPlan.isCandidate(workout))
        // Distance-only mixed segments lack a validated one-session capture
        // adapter. Reject rather than fabricate GPS, elapsed time or HR.
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(workout, device: .iPhone),
            .unavailable
        )
    }
}
